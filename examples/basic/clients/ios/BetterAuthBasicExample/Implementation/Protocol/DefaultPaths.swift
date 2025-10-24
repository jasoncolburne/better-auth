import Foundation
import BetterAuth

func createDefaultPaths() -> IAuthenticationPaths {
    return IAuthenticationPaths(
        account: AccountPaths(
            create: "/account/create",
            recover: "/account/recover",
            delete: "/account/delete"
        ),
        session: SessionPaths(
            request: "/session/request",
            create: "/session/create",
            refresh: "/session/refresh"
        ),
        device: DevicePaths(
            rotate: "/device/rotate",
            link: "/device/link",
            unlink: "/device/unlink"
        ),
        recovery: RecoveryPaths(
            change: "/recovery/change"
        )
    )
}
