#include "MotionTextEngine.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/photo.hpp>
#include <opencv2/video/tracking.hpp>
#include <opencv2/calib3d.hpp>
#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>

namespace {
struct Engine {
    cv::Mat previous_gray;
    cv::Mat previous_clean;
    cv::Mat previous_mask;
    cv::Rect box;
    std::vector<cv::Point2f> points;
    MTE_Config cfg{};
    int frame_w = 0, frame_h = 0;
    bool has_history = false;
};

static cv::Rect clampRect(cv::Rect r, int w, int h) {
    r.x = std::max(0, r.x); r.y = std::max(0, r.y);
    r.width = std::max(0, std::min(r.width, w - r.x));
    r.height = std::max(0, std::min(r.height, h - r.y));
    return r;
}
static cv::Mat wrapBgr(const uint8_t* p, int w, int h, int stride) {
    return cv::Mat(h, w, CV_8UC3, const_cast<uint8_t*>(p), static_cast<size_t>(stride));
}
static cv::Mat wrapMask(const uint8_t* p, int w, int h, int stride) {
    return cv::Mat(h, w, CV_8UC1, const_cast<uint8_t*>(p), static_cast<size_t>(stride));
}
static cv::Rect maskBounds(const cv::Mat& mask) {
    std::vector<cv::Point> nz;
    cv::findNonZero(mask, nz);
    if (nz.empty()) return {};
    return cv::boundingRect(nz);
}
static void detectPoints(Engine& e, const cv::Mat& gray) {
    e.points.clear();
    cv::Rect safe = clampRect(e.box, gray.cols, gray.rows);
    if (safe.width < 4 || safe.height < 4) return;
    cv::Mat roi = gray(safe);
    std::vector<cv::Point2f> local;
    cv::goodFeaturesToTrack(roi, local, std::max(40, e.cfg.max_corners),
                            0.01, 2.0, cv::Mat(), 3, false, 0.04);
    e.points.reserve(local.size());
    for (const auto& q : local) e.points.emplace_back(q.x + safe.x, q.y + safe.y);
}
static float medianValue(std::vector<float>& v) {
    if (v.empty()) return 0.0f;
    const size_t n = v.size();
    std::nth_element(v.begin(), v.begin() + n/2, v.end());
    return v[n/2];
}

/* Similarity transform (translation + rotation + scale) for the target region.
   This is deliberately independent of font colour. */
static cv::Rect trackBox(Engine& e, const cv::Mat& gray) {
    if (e.points.size() < 4) detectPoints(e, e.previous_gray);
    if (e.points.size() < 4) return clampRect(e.box, gray.cols, gray.rows);

    std::vector<cv::Point2f> next, goodPrev, goodNext;
    std::vector<unsigned char> status;
    std::vector<float> errors;
    cv::calcOpticalFlowPyrLK(e.previous_gray, gray, e.points, next,
                             status, errors, cv::Size(31,31), 4,
                             cv::TermCriteria(cv::TermCriteria::COUNT|cv::TermCriteria::EPS, 30, 0.01),
                             cv::OPTFLOW_LK_GET_MIN_EIGENVALS, 1e-4);
    for (size_t i=0; i<status.size(); ++i) {
        if (status[i] && errors[i] < 25.0f &&
            next[i].x >= 0 && next[i].y >= 0 &&
            next[i].x < gray.cols && next[i].y < gray.rows) {
            goodPrev.push_back(e.points[i]);
            goodNext.push_back(next[i]);
        }
    }

    if (goodNext.size() >= 4) {
        cv::Mat inliers;
        cv::Mat A = cv::estimateAffinePartial2D(goodPrev, goodNext, inliers,
                                                cv::RANSAC, 2.5, 1500, 0.98, 10);
        if (!A.empty()) {
            double a=A.at<double>(0,0), b=A.at<double>(0,1);
            double c=A.at<double>(1,0), d=A.at<double>(1,1);
            std::vector<cv::Point2f> corners = {
                {(float)e.box.x,(float)e.box.y},
                {(float)(e.box.x+e.box.width),(float)e.box.y},
                {(float)e.box.x,(float)(e.box.y+e.box.height)},
                {(float)(e.box.x+e.box.width),(float)(e.box.y+e.box.height)}
            };
            for (auto& p: corners) {
                float x=p.x, y=p.y;
                p.x=(float)(a*x+b*y+A.at<double>(0,2));
                p.y=(float)(c*x+d*y+A.at<double>(1,2));
            }
            cv::Rect nr = cv::boundingRect(corners);
            if (nr.width > 2 && nr.height > 2) e.box=nr;
        } else {
            std::vector<float> dx,dy;
            for(size_t i=0;i<goodPrev.size();++i) {
                dx.push_back(goodNext[i].x-goodPrev[i].x);
                dy.push_back(goodNext[i].y-goodPrev[i].y);
            }
            e.box.x += (int)std::lround(medianValue(dx));
            e.box.y += (int)std::lround(medianValue(dy));
        }
        e.points.swap(goodNext);
    } else {
        e.points.clear();
    }
    e.box=clampRect(e.box,gray.cols,gray.rows);
    if ((int)e.points.size() < e.cfg.min_tracked_points) detectPoints(e,gray);
    return e.box;
}

/* Estimate camera/background motion from pixels outside the text area. */
static bool estimateBackgroundWarp(const Engine& e, const cv::Mat& currentGray,
                                   const cv::Mat& currentMask, cv::Mat& affine,
                                   float& quality) {
    quality=0.0f;
    if (!e.has_history || e.previous_gray.empty() || e.previous_clean.empty()) return false;

    /* Reject hard cuts / large flashes before using stale temporal content. */
    cv::Mat valid(e.frame_h,e.frame_w,CV_8UC1,cv::Scalar(255));
    cv::Mat cutExclusion, cutDiff;
    cv::bitwise_or(e.previous_mask, currentMask, cutExclusion);
    cv::dilate(cutExclusion, cutExclusion,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,cv::Size(25,25)));
    valid.setTo(0,cutExclusion);
    cv::absdiff(e.previous_gray,currentGray,cutDiff);
    const double sceneDelta=cv::mean(cutDiff,valid)[0];
    if(sceneDelta>42.0) return false;

    cv::Mat featureMask(e.frame_h,e.frame_w,CV_8UC1,cv::Scalar(255));
    cv::Mat exclusion;
    cv::dilate(e.previous_mask, exclusion,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,cv::Size(31,31)));
    featureMask.setTo(0,exclusion);
    cv::Mat currentExclusion;
    cv::dilate(currentMask,currentExclusion,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,cv::Size(31,31)));
    featureMask.setTo(0,currentExclusion);

    std::vector<cv::Point2f> p0,p1;
    cv::goodFeaturesToTrack(e.previous_gray,p0,500,0.01,8.0,featureMask,3,false,0.04);
    if(p0.size()<12) return false;

    std::vector<unsigned char> st;
    std::vector<float> err;
    cv::calcOpticalFlowPyrLK(e.previous_gray,currentGray,p0,p1,st,err,
                             cv::Size(31,31),4);
    std::vector<cv::Point2f> a,b;
    for(size_t i=0;i<st.size();++i) {
        if(st[i] && err[i]<25.0f && p1[i].x>=0 && p1[i].y>=0 &&
           p1[i].x<currentGray.cols && p1[i].y<currentGray.rows) {
            a.push_back(p0[i]); b.push_back(p1[i]);
        }
    }
    if(a.size()<12) return false;

    cv::Mat inliers;
    cv::Mat A=cv::estimateAffinePartial2D(a,b,inliers,cv::RANSAC,3.0,2000,0.98,10);
    if(A.empty()) return false;
    int inlierCount=0;
    for(int i=0;i<inliers.rows;++i) if(inliers.at<unsigned char>(i,0)) ++inlierCount;
    quality=(float)inlierCount/(float)std::max<size_t>(1,a.size());
    if(inlierCount<10 || quality<0.30f) return false;

    affine=A.clone();
    return true;
}

static int processFrame(Engine& e, uint8_t* data, int w, int h, int stride,
                        const uint8_t* suppliedMask, int maskStride,
                        float maskConfidence, MTE_Rect* out) {
    if(!data || w<=0 || h<=0 || stride<w*3) return -1;
    if(w!=e.frame_w || h!=e.frame_h) return -2;

    cv::Mat bgr=wrapBgr(data,w,h,stride);
    cv::Mat original=bgr.clone();
    cv::Mat gray;
    cv::cvtColor(original,gray,cv::COLOR_BGR2GRAY);

    cv::Mat mask(h,w,CV_8UC1,cv::Scalar(0));
    cv::Rect r;
    if(suppliedMask && maskStride>=w && maskConfidence>=0.35f) {
        cv::Mat external=wrapMask(suppliedMask,w,h,maskStride);
        cv::threshold(external,mask,0,255,cv::THRESH_BINARY);
        r=maskBounds(mask);
        if(r.width<2 || r.height<2) return -4;
        e.box=r;
        e.points.clear();
        detectPoints(e,gray);
    } else {
        r=trackBox(e,gray);
        if(r.width<2 || r.height<2) return -3;
        int pad=std::max(0,e.cfg.mask_padding);
        cv::Rect mr=clampRect(cv::Rect(r.x-pad,r.y-pad,r.width+2*pad,r.height+2*pad),w,h);
        cv::rectangle(mask,mr,cv::Scalar(255),cv::FILLED);
    }

    /* Dilate slightly to cover antialiased glyph edges. */
    int pad=std::max(0,e.cfg.mask_padding);
    if(pad>0) cv::dilate(mask,mask,cv::getStructuringElement(
        cv::MORPH_ELLIPSE,cv::Size(2*pad+1,2*pad+1)));

    cv::Mat repaired=original.clone();
    cv::Rect workRect=maskBounds(mask);
    int margin=std::max(24,e.cfg.inpaint_radius*5);
    workRect=clampRect(cv::Rect(workRect.x-margin,workRect.y-margin,
                               workRect.width+2*margin,workRect.height+2*margin),w,h);
    if(workRect.width<2 || workRect.height<2) return -4;

    int method=e.cfg.inpaint_method==1?cv::INPAINT_NS:cv::INPAINT_TELEA;
    cv::Mat repairedRoi;
    cv::inpaint(original(workRect),mask(workRect),repairedRoi,
                (double)std::max(1,e.cfg.inpaint_radius),method);
    repairedRoi.copyTo(repaired(workRect));

    /* Low-latency temporal repair: warp only the needed patch from the
       previous CLEAN frame. Inpainting remains the seam-safe fallback. */
    cv::Mat bgAffine;
    float bgQuality=0.0f;
    if(estimateBackgroundWarp(e,gray,mask,bgAffine,bgQuality) && bgQuality>=0.42f) {
        cv::Mat inner;
        int erosion=std::max(1,pad+1);
        cv::erode(mask(workRect),inner,cv::getStructuringElement(
            cv::MORPH_ELLIPSE,cv::Size(2*erosion+1,2*erosion+1)));
        bgAffine.at<double>(0,2)-=workRect.x;
        bgAffine.at<double>(1,2)-=workRect.y;
        cv::Mat warpedRoi;
        cv::warpAffine(e.previous_clean,warpedRoi,bgAffine,workRect.size(),
                       cv::INTER_LINEAR,cv::BORDER_REFLECT);
        warpedRoi.copyTo(repaired(workRect),inner);
    }

    repaired.copyTo(bgr);
    e.previous_gray=gray;
    e.previous_clean=repaired.clone();
    e.previous_mask=mask.clone();
    e.has_history=true;

    if(out) *out=MTE_Rect{r.x,r.y,r.width,r.height};
    return 0;
}
}

MTE_Handle MTE_CALL MTE_Create(const uint8_t* first,int w,int h,int stride,
                               MTE_Rect region,const MTE_Config* config) {
    try {
        if(!first||w<=0||h<=0||stride<w*3) return nullptr;
        auto e=std::make_unique<Engine>();
        e->cfg=config?*config:MTE_Config{5,2,250,20,0,0};
        if(e->cfg.inpaint_radius<=0)e->cfg.inpaint_radius=5;
        if(e->cfg.max_corners<=0)e->cfg.max_corners=250;
        if(e->cfg.min_tracked_points<=0)e->cfg.min_tracked_points=20;
        e->frame_w=w;e->frame_h=h;
        e->box=clampRect(cv::Rect(region.x,region.y,region.width,region.height),w,h);
        if(e->box.width<2||e->box.height<2)return nullptr;
        cv::Mat bgr=wrapBgr(first,w,h,stride);
        cv::cvtColor(bgr,e->previous_gray,cv::COLOR_BGR2GRAY);
        e->previous_clean=bgr.clone();
        e->previous_mask=cv::Mat(h,w,CV_8UC1,cv::Scalar(0));
        detectPoints(*e,e->previous_gray);
        e->has_history=true;
        return e.release();
    } catch(...) { return nullptr; }
}
int MTE_CALL MTE_Process(MTE_Handle handle,uint8_t* data,int w,int h,int stride,MTE_Rect* out) {
    try { if(!handle)return -1; return processFrame(*static_cast<Engine*>(handle),data,w,h,stride,nullptr,0,0.0f,out); }
    catch(...) { return -10; }
}
int MTE_CALL MTE_ProcessMask(MTE_Handle handle,uint8_t* data,int w,int h,int stride,
                             const uint8_t* mask,int maskStride,float confidence,MTE_Rect* out) {
    try {
        if(!handle||!mask||maskStride<w)return -1;
        return processFrame(*static_cast<Engine*>(handle),data,w,h,stride,mask,maskStride,
                            std::max(0.0f,std::min(1.0f,confidence)),out);
    } catch(...) { return -10; }
}
int MTE_CALL MTE_Reset(MTE_Handle handle,const uint8_t* data,int w,int h,int stride,MTE_Rect region) {
    try {
        if(!handle||!data||w<=0||h<=0||stride<w*3)return -1;
        Engine& e=*static_cast<Engine*>(handle);
        if(w!=e.frame_w||h!=e.frame_h)return -2;
        e.box=clampRect(cv::Rect(region.x,region.y,region.width,region.height),w,h);
        if(e.box.width<2||e.box.height<2)return -3;
        cv::Mat bgr=wrapBgr(data,w,h,stride);
        cv::cvtColor(bgr,e.previous_gray,cv::COLOR_BGR2GRAY);
        e.previous_clean=bgr.clone();
        e.previous_mask=cv::Mat(h,w,CV_8UC1,cv::Scalar(0));
        e.points.clear();detectPoints(e,e.previous_gray);
        e.has_history=true;
        return 0;
    } catch(...) { return -10; }
}
void MTE_CALL MTE_Destroy(MTE_Handle handle) { delete static_cast<Engine*>(handle); }
const char* MTE_CALL MTE_Version(void) { return "0.3.0-live"; }
