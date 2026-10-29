#import "RdpBridge.h"
#include "../../../native/bridge/engine_bridge.h"

@implementation RdpBridge
- (void)connect {
    RdpEngineHandle* h = rdp_engine_create();
    rdp_engine_connect(h, "127.0.0.1", 3389, "", "", "");
    rdp_engine_destroy(h);
}
@end
