#include "MotionTextEngine.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/photo.hpp>
#include <opencv2/video/tracking.hpp>
#include <opencv2/videoio.hpp>\n#include <tesseract/baseapi.h>\n#include <tesseract/resultiterator.h>
#include <windows.h>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <cwchar>
#include <mutex>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <atomic>

namespace {
thread_local std::string g_error;
void setError(const char* s) { g_error = s ? s : "Unknown error"; }

std::string toUtf8(const wchar_t* value) {
    if (!value) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 1) return {};
    std::string out(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), n, nullptr, nullptr);
    out.pop_back();
    return out;
}
cv::Rect clampRect(cv::Rect r, int w, int h) {
    r.x=std::max(0,r.x); r.y=std::max(0,r.y);
    r.width=std::max(0,std::min(r.width,w-r.x));
    r.height=std::max(0,std::min(r.height,h-r.y));
    return r;
}
struct Tracker {
    cv::Mat previousGray;
    cv::Rect box;
    std::vector<cv::Point2f> points;
    std::vector<cv::Point2f> quad;
    int lostFrames = 0;
    float lastConfidence = 1.0f;
    MTE_Config cfg{};
};
void detectPoints(Tracker& t,const cv::Mat& gray) {
    t.points.clear();
    cv::Rect r=clampRect(t.box,gray.cols,gray.rows);
    if(r.width<4||r.height<4) return;
    std::vector<cv::Point2f> local;
    cv::goodFeaturesToTrack(gray(r),local,std::max(24,t.cfg.max_corners),
                            0.01,3.0,cv::Mat(),3,false,0.04);
    for(const auto& p:local) t.points.emplace_back(p.x+r.x,p.y+r.y);
}
void initTracker(Tracker& t,const cv::Mat& frame,MTE_Rect region,const MTE_Config& cfg) {
    t.cfg=cfg;
    t.box=clampRect(cv::Rect(region.x,region.y,region.width,region.height),frame.cols,frame.rows);
    t.quad = {
        cv::Point2f((float)t.box.x,(float)t.box.y),
        cv::Point2f((float)(t.box.x+t.box.width),(float)t.box.y),
        cv::Point2f((float)(t.box.x+t.box.width),(float)(t.box.y+t.box.height)),
        cv::Point2f((float)t.box.x,(float)(t.box.y+t.box.height))
    };
    cv::cvtColor(frame,t.previousGray,cv::COLOR_BGR2GRAY);
    detectPoints(t,t.previousGray);
}
bool reacquireTemplate(Tracker& t,const cv::Mat& gray) {
    if(t.cfg.reacquire_search_radius<=0 || t.box.width<8 || t.box.height<6) return false;
    cv::Rect templRect=clampRect(t.box,t.previousGray.cols,t.previousGray.rows);
    if(templRect.width<8 || templRect.height<6) return false;
    cv::Mat templ=t.previousGray(templRect);
    int rad=t.cfg.reacquire_search_radius;
    cv::Rect search=clampRect(cv::Rect(t.box.x-rad,t.box.y-rad,
                                      t.box.width+2*rad,t.box.height+2*rad),
                              gray.cols,gray.rows);
    if(search.width<templ.cols || search.height<templ.rows) return false;
    cv::Mat result;
    cv::matchTemplate(gray(search),templ,result,cv::TM_CCOEFF_NORMED);
    double minVal=0,maxVal=0;
    cv::Point minLoc,maxLoc;
    cv::minMaxLoc(result,&minVal,&maxVal,&minLoc,&maxLoc);
    t.lastConfidence=(float)maxVal;
    if(maxVal < (double)t.cfg.reacquire_min_score) return false;
    int newX=search.x+maxLoc.x, newY=search.y+maxLoc.y;
    int dx=newX-t.box.x, dy=newY-t.box.y;
    for(auto& q:t.quad) { q.x+=(float)dx; q.y+=(float)dy; }
    t.box.x=newX; t.box.y=newY;
    t.lostFrames=0;
    detectPoints(t,gray);
    return true;
}
cv::Rect updateTracker(Tracker& t,const cv::Mat& gray) {
    if(t.points.size()<4) detectPoints(t,t.previousGray);
    if(t.points.size()>=4) {
        std::vector<cv::Point2f> next, oldGood, newGood;
        std::vector<unsigned char> status;
        std::vector<float> errors;
        cv::calcOpticalFlowPyrLK(t.previousGray,gray,t.points,next,status,errors,cv::Size(21,21),3);
        for(size_t i=0;i<status.size();++i) {
            if(status[i] && errors[i]<40.0f && next[i].x>=0 && next[i].y>=0 &&
               next[i].x<gray.cols && next[i].y<gray.rows) {
                oldGood.push_back(t.points[i]);
                newGood.push_back(next[i]);
            }
        }
        if(newGood.size()>=4 && t.quad.size()==4) {
            cv::Mat inliers;
            cv::Mat affine=cv::estimateAffinePartial2D(oldGood,newGood,inliers,cv::RANSAC,3.0,2000,0.99,10);
            if(!affine.empty()) {
                std::vector<cv::Point2f> transformed;
                cv::transform(t.quad,transformed,affine);
                bool valid=true;
                for(const auto& q:transformed)
                    if(!std::isfinite(q.x)||!std::isfinite(q.y)) valid=false;
                if(valid) t.quad.swap(transformed);
            }
            t.points.swap(newGood);
        } else {
            t.points.clear();
            ++t.lostFrames;
            if(!reacquireTemplate(t,gray) && t.lostFrames>0)
                t.lastConfidence=0.0f;
        }
    }
    if(t.points.size()<4 && t.lostFrames==0) {
        ++t.lostFrames;
        reacquireTemplate(t,gray);
    }
    if(t.quad.size()==4) {
        float minx=(float)gray.cols,miny=(float)gray.rows,maxx=0,maxy=0;
        for(const auto& q:t.quad) {
            minx=std::min(minx,q.x); miny=std::min(miny,q.y);
            maxx=std::max(maxx,q.x); maxy=std::max(maxy,q.y);
        }
        t.box=clampRect(cv::Rect((int)std::floor(minx),(int)std::floor(miny),
                                  (int)std::ceil(maxx-minx),(int)std::ceil(maxy-miny)),
                        gray.cols,gray.rows);
        for(auto& q:t.quad) {
            q.x=std::max(0.0f,std::min((float)(gray.cols-1),q.x));
            q.y=std::max(0.0f,std::min((float)(gray.rows-1),q.y));
        }
    }
    if((int)t.points.size()<t.cfg.min_tracked_points) detectPoints(t,gray);
    return t.box;
}
void inpaintRegion(cv::Mat& frame,const Tracker& tracker) {
    const MTE_Config& cfg=tracker.cfg;
    cv::Mat mask(frame.rows,frame.cols,CV_8UC1,cv::Scalar(0));
    if(tracker.quad.size()==4) {
        std::vector<cv::Point> polygon;
        for(const auto& q:tracker.quad)
            polygon.emplace_back((int)std::lround(q.x),(int)std::lround(q.y));
        cv::fillConvexPoly(mask,polygon,cv::Scalar(255),cv::LINE_AA);
        int pad=std::max(0,cfg.mask_padding);
        if(pad>0) {
            int k=pad*2+1;
            cv::dilate(mask,mask,cv::getStructuringElement(cv::MORPH_ELLIPSE,cv::Size(k,k)));
        }
    } else {
        cv::Rect r=clampRect(tracker.box,frame.cols,frame.rows);
        cv::rectangle(mask,r,cv::Scalar(255),cv::FILLED);
    }
    if(cv::countNonZero(mask)==0) return;
    cv::Mat repaired;
    cv::inpaint(frame,mask,repaired,(double)std::max(1,cfg.inpaint_radius),
                cfg.inpaint_method==1?cv::INPAINT_NS:cv::INPAINT_TELEA);
    repaired.copyTo(frame);
}


std::wstring normalizeTargetText(const wchar_t* text) {
    std::wstring out;
    if (!text) return out;
    for (const wchar_t* p=text; *p; ++p) {
        if (*p==L' ' || *p==L'\t' || *p==L'\r' || *p==L'\n') continue;
        wchar_t c=*p;
        if (c>=L'a' && c<=L'z') c=(wchar_t)(c-L'a'+L'A');
        out.push_back(c);
    }
    return out;
}
std::wstring utf8ToWideText(const char* text) {
    if (!text) return {};
    int n=MultiByteToWideChar(CP_UTF8,0,text,-1,nullptr,0);
    if (n<=1) return {};
    std::wstring out((size_t)n,L'\0');
    MultiByteToWideChar(CP_UTF8,0,text,-1,out.data(),n);
    out.pop_back();
    return out;
}
struct OcrHit { cv::Rect box; int confidence; };
class TextScanner {
public:
    bool initialize() {
        if (api_.Init("tessdata","eng",tesseract::OEM_LSTM_ONLY)!=0) return false;
        api_.SetPageSegMode(tesseract::PSM_SPARSE_TEXT);
        api_.SetVariable("user_defined_dpi","120");
        return true;
    }
    std::vector<OcrHit> find(const cv::Mat& frame,const std::wstring& target,int minConfidence) {
        std::vector<OcrHit> hits;
        if (frame.empty()) return hits;
        cv::Mat gray;
        cv::cvtColor(frame,gray,cv::COLOR_BGR2GRAY);
        api_.SetImage(gray.data,gray.cols,gray.rows,1,(int)gray.step);
        if (api_.Recognize(nullptr)!=0) return hits;
        tesseract::ResultIterator* it=api_.GetIterator();
        if (!it) return hits;
        do {
            char* word=it->GetUTF8Text(tesseract::RIL_WORD);
            if (!word) continue;
            std::wstring candidate=utf8ToWideText(word);
            delete[] word;
            candidate=normalizeTargetText(candidate.c_str());
            int confidence=(int)it->Confidence(tesseract::RIL_WORD);
            if (candidate==target && confidence>=minConfidence) {
                int x1=0,y1=0,x2=0,y2=0;
                if (it->BoundingBox(tesseract::RIL_WORD,&x1,&y1,&x2,&y2))
                    hits.push_back({cv::Rect(x1,y1,x2-x1,y2-y1),confidence});
            }
        } while (it->Next(tesseract::RIL_WORD));
        return hits;
    }
private:
    tesseract::TessBaseAPI api_;
};
struct TargetInstance {
    Tracker tracker;
    int64_t lastSeenFrame=0;
    int confidence=0;
};

MTE_Config defaultsFor(int mode) {
    MTE_Config c{};
    c.mode=mode; c.inpaint_radius=5; c.mask_padding=3; c.max_corners=100;
    c.min_tracked_points=12; c.inpaint_method=0; c.live_buffer_size=1;
    c.reconnect_attempts=3; c.reconnect_delay_ms=700; c.movie_temporal_radius=2; c.reacquire_search_radius=160; c.reacquire_min_score=0.58f; c.ocr_interval_frames=8; c.max_instances=8; c.max_absent_seconds=0; c.min_ocr_confidence=65;
    return c;
}
bool openSource(cv::VideoCapture& cap,int type,const std::string& src,int buffer) {
    if(type==MTE_SOURCE_CAPTURE_DEVICE) {
        int index=0; try { index=std::stoi(src); } catch(...) { return false; }
        if(!cap.open(index,cv::CAP_DSHOW)) return cap.open(index,cv::CAP_ANY);
        return true;
    }
    if(type==MTE_SOURCE_RTSP || type==MTE_SOURCE_UDP) {
        cap.set(cv::CAP_PROP_BUFFERSIZE,std::max(1,buffer));
        return cap.open(src,cv::CAP_FFMPEG) || cap.open(src,cv::CAP_ANY);
    }
    return cap.open(src,cv::CAP_ANY);
}
}

int MTE_CALL MTE_Process(int source_type,const wchar_t* source,const wchar_t* output,
    MTE_Rect region,const wchar_t* targetText,const MTE_Config* userCfg,MTE_ProgressCallback progress,void* user) {
    try {
        g_error.clear();
        if(!source||!output) { setError("Source or output path is null"); return -1; }
        if(source_type<0||source_type>3) { setError("Invalid source type"); return -2; }
        MTE_Config cfg=userCfg?*userCfg:defaultsFor(MTE_MODE_LIVE_BALANCED);
        if(cfg.inpaint_radius<=0) cfg.inpaint_radius=5;
        if(cfg.max_corners<=0) cfg.max_corners=100;
        if(cfg.min_tracked_points<=0) cfg.min_tracked_points=12;
        if(cfg.live_buffer_size<=0) cfg.live_buffer_size=1;
        if(cfg.reacquire_search_radius<0) cfg.reacquire_search_radius=0;
        if(cfg.reacquire_min_score<=0.0f) cfg.reacquire_min_score=0.58f;
        if(cfg.ocr_interval_frames<=0) cfg.ocr_interval_frames=8;
        if(cfg.max_instances<=0) cfg.max_instances=8;
        if(cfg.min_ocr_confidence<=0) cfg.min_ocr_confidence=65;
        const std::wstring target=normalizeTargetText(targetText);
        if(target.empty()) { setError("Enter the target code manually"); return -8; }
        const std::string src=toUtf8(source), dst=toUtf8(output);
        cv::VideoCapture cap;
        bool opened=openSource(cap,source_type,src,cfg.live_buffer_size);
        if(!opened) { setError("Unable to open input source. Check FFmpeg support, URL and device permissions."); return -3; }

        cv::Mat first;
        if(!cap.read(first)||first.empty()) { setError("Input opened but no first frame was received"); return -4; }
        TextScanner scanner;
        if(!scanner.initialize()) {
            setError("Tesseract initialization failed; tessdata/eng.traineddata must be beside the application.");
            return -9;
        }
        std::vector<TargetInstance> instances;
        auto initialHits=scanner.find(first,target,cfg.min_ocr_confidence);
        for(const auto& hit:initialHits) {
            if((int)instances.size()>=cfg.max_instances) break;
            TargetInstance item;
            MTE_Rect r{hit.box.x,hit.box.y,hit.box.width,hit.box.height};
            initTracker(item.tracker,first,r,cfg);
            item.lastSeenFrame=0;
            item.confidence=hit.confidence;
            instances.push_back(std::move(item));
        }


        double fps=cap.get(cv::CAP_PROP_FPS);
        if(!(fps>0.1&&fps<240.0)) fps=30.0;
        cv::VideoWriter writer;
        bool outputIsStream=(dst.rfind("rtmp://",0)==0||dst.rfind("udp://",0)==0||dst.rfind("rtsp://",0)==0);
        int fourcc=cv::VideoWriter::fourcc('M','J','P','G');
        if(!outputIsStream) {
            std::string ext=dst.substr(dst.find_last_of('.')==std::string::npos?dst.size():dst.find_last_of('.'));
            if(ext==".mp4"||ext==".MP4") fourcc=cv::VideoWriter::fourcc('m','p','4','v');
        }
        if(!writer.open(dst,fourcc,fps,first.size(),true)) {
            setError("Unable to open output. Try an AVI file or a supported streaming output URL.");
            return -6;
        }

        bool live=(source_type!=MTE_SOURCE_FILE);
        double total=live?0.0:cap.get(cv::CAP_PROP_FRAME_COUNT);
        int frameIndex=0;
        cv::Mat gray;

        auto processFrame = [&](cv::Mat& current) -> bool {
            cv::Mat processed=current.clone();
            if(frameIndex>0) {
                cv::cvtColor(current,gray,cv::COLOR_BGR2GRAY);
                for(auto& item:instances) {
                    cv::Rect r=updateTracker(item.tracker,gray);
                    if(r.width>=2 && r.height>=2) {
                        inpaintRegion(processed,item.tracker);
                        gray.copyTo(item.tracker.previousGray);
                    }
                }
            }
            if(frameIndex % cfg.ocr_interval_frames == 0) {
                auto hits=scanner.find(current,target,cfg.min_ocr_confidence);
                for(const auto& hit:hits) {
                    bool matched=false;
                    for(auto& item:instances) {
                        cv::Rect overlap=item.tracker.box & hit.box;
                        double ratio=(double)overlap.area()/std::max(1,std::min(item.tracker.box.area(),hit.box.area()));
                        if(ratio>0.25) {
                            MTE_Rect r{hit.box.x,hit.box.y,hit.box.width,hit.box.height};
                            initTracker(item.tracker,current,r,cfg);
                            item.lastSeenFrame=frameIndex;
                            item.confidence=hit.confidence;
                            matched=true;
                            break;
                        }
                    }
                    if(!matched && (int)instances.size()<cfg.max_instances) {
                        TargetInstance item;
                        MTE_Rect r{hit.box.x,hit.box.y,hit.box.width,hit.box.height};
                        initTracker(item.tracker,current,r,cfg);
                        item.lastSeenFrame=frameIndex;
                        item.confidence=hit.confidence;
                        instances.push_back(std::move(item));
                    }
                }
            }
            writer.write(processed);
            ++frameIndex;
            if(progress&&!live&&total>0)
                progress(std::min(100,(int)(100.0*frameIndex/total)),user);
            return true;
        };

        if(!live) {
            cv::Mat current=first;
            if(!processFrame(current)) { writer.release(); cap.release(); return -7; }
            cv::Mat frame;
            while(cap.read(frame) && !frame.empty()) {
                if(!processFrame(frame)) { writer.release(); cap.release(); return -7; }
            }
        } else {
            /* Live mode: capture/decode runs independently from tracking/inpainting.
               Queue is deliberately bounded; when full, discard the oldest waiting
               frame to prevent latency from accumulating behind a slow processor. */
            const size_t queueLimit=(size_t)std::max(1,std::min(4,cfg.live_buffer_size));
            std::mutex queueMutex;
            std::condition_variable queueReady;
            std::deque<cv::Mat> frameQueue;
            std::atomic<bool> producerDone{false};
            std::atomic<bool> stopProducer{false};
            std::atomic<int> droppedFrames{0};

            std::thread producer([&]() {
                cv::Mat incoming;
                while(!stopProducer.load()) {
                    if(!cap.read(incoming) || incoming.empty()) {
                        cap.release();
                        bool recovered=false;
                        for(int attempt=0;attempt<std::max(0,cfg.reconnect_attempts);++attempt) {
                            std::this_thread::sleep_for(std::chrono::milliseconds(std::max(100,cfg.reconnect_delay_ms)));
                            if(openSource(cap,source_type,src,cfg.live_buffer_size) &&
                               cap.read(incoming) && !incoming.empty()) {
                                recovered=true;
                                break;
                            }
                            cap.release();
                        }
                        if(!recovered) break;
                    }
                    {
                        std::lock_guard<std::mutex> lock(queueMutex);
                        if(frameQueue.size()>=queueLimit) {
                            frameQueue.pop_front();
                            ++droppedFrames;
                        }
                        frameQueue.emplace_back(incoming.clone());
                    }
                    queueReady.notify_one();
                }
                producerDone.store(true);
                queueReady.notify_all();
            });

            cv::Mat current=first;
            bool ok=processFrame(current);
            while(ok) {
                cv::Mat nextFrame;
                {
                    std::unique_lock<std::mutex> lock(queueMutex);
                    queueReady.wait(lock,[&](){ return !frameQueue.empty() || producerDone.load(); });
                    if(frameQueue.empty() && producerDone.load()) break;
                    nextFrame=std::move(frameQueue.front());
                    frameQueue.pop_front();
                }
                ok=processFrame(nextFrame);
            }
            if(!ok) setError("Live frame processing failed");
            stopProducer.store(true);
            producerDone.store(true);
            queueReady.notify_all();
            if(producer.joinable()) producer.join();
            /* droppedFrames is intentionally retained for future diagnostics API. */
            (void)droppedFrames.load();
        }
        writer.release(); cap.release();
        if(!g_error.empty()) return -7;
        if(progress&&!live) progress(100,user);
        return 0;
    } catch(const cv::Exception& e) { setError(e.what()); return -20; }
      catch(const std::exception& e) { setError(e.what()); return -21; }
      catch(...) { setError("Unknown native exception"); return -22; }
}
const char* MTE_CALL MTE_Version(void) { return "0.4.0"; }
const char* MTE_CALL MTE_LastError(void) { return g_error.c_str(); }
