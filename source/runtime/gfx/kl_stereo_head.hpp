#pragma once
#include <cmath>
#include <openxr/openxr.h>

// Use one LocateViews snapshot for head and eye transforms. Averaging the
// rotations also handles symmetric eye cant; align quaternion hemispheres
// first because q and -q represent the same orientation.
static inline bool kl_stereo_head(const XrView *views, unsigned count,
                                  XrViewStateFlags flags, XrPosef *head) {
    constexpr XrViewStateFlags required = XR_VIEW_STATE_POSITION_VALID_BIT |
                                          XR_VIEW_STATE_ORIENTATION_VALID_BIT;
    if (!views || !head || count != 2 || (flags & required) != required) return false;
    auto a = views[0].pose.orientation, b = views[1].pose.orientation;
    float dot = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
    float sign = dot < 0 ? -1.f : 1.f;
    XrQuaternionf q{a.x+sign*b.x, a.y+sign*b.y, a.z+sign*b.z, a.w+sign*b.w};
    float norm = std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);
    if (!std::isfinite(norm) || norm < 1e-6f) return false;
    q = {q.x/norm, q.y/norm, q.z/norm, q.w/norm};
    auto p = views[0].pose.position, r = views[1].pose.position;
    XrVector3f mid{(p.x+r.x)*.5f, (p.y+r.y)*.5f, (p.z+r.z)*.5f};
    if (!std::isfinite(mid.x) || !std::isfinite(mid.y) || !std::isfinite(mid.z)) return false;
    *head = {q, mid};
    return true;
}
