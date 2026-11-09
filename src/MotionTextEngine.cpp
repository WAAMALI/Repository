#include "MotionTextEngine.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/video/tracking.hpp>
#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>

namespace {
struct Engine {
    cv::Mat previous_gray;
    cv::Rect box;
    std::vector<cv::Point2f> points;
    MTE_Config cfg{};
    int frame_w = 0, frame_h = 0;
};

static cv::Rect clampRect(cv::Rect r, int w, int h) {
    r.x = std::max(0, r.x); r.y = std::max(0, r.y);
    r.width = std::min(r.width, w - r.x);
    r.height = std::min(r.height, h - r.y);
    return r;
}

static cv::Mat wrapBgr(const uint8_t* p, int w, int h, int stride) {
    return cv::Mat(h, w, CV_8UC3, const_cast<uint8_t*>(p), static_cast<size_t>(stride));
}

static void detectPoints(Engine& e, const cv::Mat& gray) {
    e.points.clear();
    cv::Rect safe = clampRect(e.box, gray.cols, gray.rows);
    if (safe.width < 4 || safe.height < 4) return;
    cv::Mat roi = gray(safe);
    std::vector<cv::Point2f> local;
    cv::goodFeaturesToTrack(roi, local, std::max(20, e.cfg.max_corners),
                            0.01, 3.0, cv::Mat(), 3, false, 0.04);
    e.points.reserve(local.size());
    for (const auto& p : local)
        e.points.emplace_back(p.x + safe.x, p.y + safe.y);
}

static cv::Rect trackBox(Engine& e, const cv::Mat& gray) {
    if (e.points.size() < 4) {
        detectPoints(e, e.previous_gray);
    }
    if (e.points.size() < 4) return e.box;

    std::vector<cv::Point2f> next;
    std::vector<unsigned char> status;
    std::vector<float> errors;
    cv::calcOpticalFlowPyrLK(e.previous_gray, gray, e.points, next,
                             status, errors, cv::Size(21,21), 3);
    std::vector<float> dx, dy;
    std::vector<cv::Point2f> good;
    for (size_t i = 0; i < status.size(); ++i) {
        if (status[i] && errors[i] < 35.0f &&
            next[i].x >= 0 && next[i].y >= 0 &&
            next[i].x < gray.cols && next[i].y < gray.rows) {
            dx.push_back(next[i].x - e.points[i].x);
            dy.push_back(next[i].y - e.points[i].y);
            good.push_back(next[i]);
        }
    }
    if (good.size() >= 3) {
        auto median = [](std::vector<float>& v) {
            const size_t n = v.size();
            std::nth_element(v.begin(), v.begin() + n/2, v.end());
            return v[n/2];
        };
        float mx = median(dx), my = median(dy);
        e.box.x += static_cast<int>(std::lround(mx));
        e.box.y += static_cast<int>(std::lround(my));
        e.points.swap(good);
    } else {
        e.points.clear();
    }

    e.box = clampRect(e.box, gray.cols, gray.rows);
    if (static_cast<int>(e.points.size()) < e.cfg.min_tracked_points)
        detectPoints(e, gray);
    return e.box;
}
}

MTE_Handle MTE_CALL MTE_Create(const uint8_t* first, int w, int h, int stride,
                               MTE_Rect region, const MTE_Config* config) {
    try {
        if (!first || w <= 0 || h <= 0 || stride < w * 3) return nullptr;
        auto e = std::make_unique<Engine>();
        e->cfg = config ? *config : MTE_Config{5, 2, 100, 12, 0, 0};
        if (e->cfg.inpaint_radius <= 0) e->cfg.inpaint_radius = 5;
        if (e->cfg.max_corners <= 0) e->cfg.max_corners = 100;
        if (e->cfg.min_tracked_points <= 0) e->cfg.min_tracked_points = 12;
        e->frame_w = w; e->frame_h = h;
        e->box = clampRect(cv::Rect(region.x, region.y, region.width, region.height), w, h);
        if (e->box.width < 2 || e->box.height < 2) return nullptr;
        cv::Mat bgr = wrapBgr(first, w, h, stride);
        cv::cvtColor(bgr, e->previous_gray, cv::COLOR_BGR2GRAY);
        detectPoints(*e, e->previous_gray);
        return e.release();
    } catch (...) { return nullptr; }
}

int MTE_CALL MTE_Process(MTE_Handle handle, uint8_t* data, int w, int h,
                         int stride, MTE_Rect* out) {
    try {
        if (!handle || !data || w <= 0 || h <= 0 || stride < w*3) return -1;
        Engine& e = *static_cast<Engine*>(handle);
        if (w != e.frame_w || h != e.frame_h) return -2;
        cv::Mat bgr = wrapBgr(data, w, h, stride);
        cv::Mat gray;
        cv::cvtColor(bgr, gray, cv::COLOR_BGR2GRAY);
        cv::Rect r = trackBox(e, gray);
        if (r.width < 2 || r.height < 2) return -3;

        cv::Mat mask(h, w, CV_8UC1, cv::Scalar(0));
        int pad = std::max(0, e.cfg.mask_padding);
        cv::Rect mr = clampRect(cv::Rect(r.x-pad, r.y-pad,
                                        r.width+2*pad, r.height+2*pad), w, h);
        cv::rectangle(mask, mr, cv::Scalar(255), cv::FILLED);
        cv::Mat repaired;
        int method = e.cfg.inpaint_method == 1 ? cv::INPAINT_NS : cv::INPAINT_TELEA;
        cv::inpaint(bgr, mask, repaired, static_cast<double>(e.cfg.inpaint_radius), method);
        repaired.copyTo(bgr);
        gray.copyTo(e.previous_gray);
        if (out) *out = MTE_Rect{r.x, r.y, r.width, r.height};
        return 0;
    } catch (...) { return -10; }
}

int MTE_CALL MTE_Reset(MTE_Handle handle, const uint8_t* data, int w, int h,
                       int stride, MTE_Rect region) {
    try {
        if (!handle || !data || w <= 0 || h <= 0 || stride < w*3) return -1;
        Engine& e = *static_cast<Engine*>(handle);
        if (w != e.frame_w || h != e.frame_h) return -2;
        e.box = clampRect(cv::Rect(region.x, region.y, region.width, region.height), w, h);
        if (e.box.width < 2 || e.box.height < 2) return -3;
        cv::Mat bgr = wrapBgr(data, w, h, stride);
        cv::cvtColor(bgr, e.previous_gray, cv::COLOR_BGR2GRAY);
        detectPoints(e, e.previous_gray);
        return 0;
    } catch (...) { return -10; }
}

void MTE_CALL MTE_Destroy(MTE_Handle handle) {
    delete static_cast<Engine*>(handle);
}

const char* MTE_CALL MTE_Version(void) { return "0.1.0"; }
