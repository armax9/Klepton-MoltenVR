#include "../runtime/gfx/kl_stereo_head.hpp"
#include <cassert>
#include <cstdio>
int main() {
    const auto flags = XR_VIEW_STATE_POSITION_VALID_BIT | XR_VIEW_STATE_ORIENTATION_VALID_BIT;
    XrView v[2]{{XR_TYPE_VIEW},{XR_TYPE_VIEW}};
    // A rotated, translated head with symmetric 10-degree eye cant.
    float yaw=.7f, cant=.174532925f;
    for(int e=0;e<2;e++) {
        float angle=yaw+(e ? cant : -cant);
        v[e].pose.orientation={0,std::sin(angle/2),0,std::cos(angle/2)};
        float x=e ? .032f : -.032f;
        v[e].pose.position={1+x*std::cos(yaw),1.7f,2-x*std::sin(yaw)};
    }
    // Opposite quaternion signs must not cancel or produce a long rotation.
    auto &q=v[1].pose.orientation;q={-q.x,-q.y,-q.z,-q.w};
    XrPosef head{};
    assert(kl_stereo_head(v,2,flags,&head));
    assert(std::fabs(head.position.x-1)<1e-6f && std::fabs(head.position.z-2)<1e-6f);
    assert(std::fabs(head.orientation.y-std::sin(yaw/2))<1e-6f);
    assert(std::fabs(head.orientation.w-std::cos(yaw/2))<1e-6f);
    assert(!kl_stereo_head(v,1,flags,&head));
    assert(!kl_stereo_head(v,2,XR_VIEW_STATE_ORIENTATION_VALID_BIT,&head));
    v[0].pose.position.x=NAN;
    assert(!kl_stereo_head(v,2,flags,&head));
    std::puts("PASS: coherent stereo head, eye cant, quaternion sign, invalid tracking");
}
