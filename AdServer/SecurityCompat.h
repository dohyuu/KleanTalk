#pragma once
#include <Security/Security.h>

// 일부 구형 SDK는 시스템 라이브러리에 있는 이 함수의 선언을 제공하지 않는다.
// https://developer.apple.com/documentation/security/secidentitycreate(_:_:_:)
SecIdentityRef _Nullable SecIdentityCreate(
    CFAllocatorRef _Nullable allocator,
    SecCertificateRef _Nonnull certificate,
    SecKeyRef _Nonnull privateKey
) CF_RETURNS_RETAINED API_AVAILABLE(macos(10.12));
