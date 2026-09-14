/// `SAMLRequest` values built from real SAML 2.0 AuthnRequest XML, not copied from
/// anywhere. Each was produced by this script, which is the whole of how they exist:
///
/// ```
/// python3 -c 'import base64,zlib
/// xml = open("authnrequest.xml","rb").read().strip()
/// c = zlib.compressobj(9, zlib.DEFLATED, -15)
/// print(base64.b64encode(c.compress(xml)+c.flush()).decode())'
/// ```
///
/// `-15` is the raw-DEFLATE window the HTTP-Redirect binding specifies, and is what
/// `COMPRESSION_ZLIB` decodes. The HTTP-POST value is the same XML under plain
/// `base64.b64encode`. `SAMLAuthnRequestTests` decodes each one back to XML, so a
/// fixture that does not round-trip fails rather than quietly weakening a case.
enum SAMLFixtures {
  /// An AuthnRequest naming its Assertion Consumer Service URL, in the HTTP-Redirect
  /// binding: raw DEFLATE, then base64.
  static let acsRedirectBinding = """
    fVJLTwIxEP4rm973KSI07CYIMZKgEkAPXkwps9Ckj7Uzq/jvLYtGvJC0l5n5HvO1IxRGN3zc0t4u\
    4b0FpOhgtEXeNUrWesudQIXcCgPISfLV+GHOiyTjjXfkpNPsDHIZIRDBk3KWRbNpyd7y7VVdbDIZ\
    34heHvfqAuKhHAzibNPfZPW1LESes+gFPAZMyQJFACK2MLNIwlIoZUU/zoZx3lvnBc+ycF5ZNA17\
    KCuoQ+2JGuRpqt1O2cQo6R26mpzVykIinUnDNc6mR/8Fi8a/JifOYmvAr8B/KAnPy/kfmWiaBA7C\
    NPpEgehSIZFFi59QbpXdKru7nMfmNIT8fr1exIun1ZpVo6MN3m3pq0tyBkhsBYlReo4YnV70MWjN\
    pgunlfyK7pw3gi5bOVbUNq67Ud4cI0cCSyEPrd3nxIMgKBn5FlhanTT/f5zqGw==
    """

  /// The same AuthnRequest in the HTTP-POST binding: base64 of the plain XML, no
  /// compression.
  static let acsPostBinding = """
    PHNhbWxwOkF1dGhuUmVxdWVzdCB4bWxuczpzYW1scD0idXJuOm9hc2lzOm5hbWVzOnRjOlNBTUw6\
    Mi4wOnByb3RvY29sIiB4bWxuczpzYW1sPSJ1cm46b2FzaXM6bmFtZXM6dGM6U0FNTDoyLjA6YXNz\
    ZXJ0aW9uIiBJRD0iXzFkM2YyYjBjLTdhNDEtNGYyZS05Yzg4LTBiNmIwZjVjMmExMSIgVmVyc2lv\
    bj0iMi4wIiBJc3N1ZUluc3RhbnQ9IjIwMjYtMDktMTRUMTI6MDA6MDBaIiBEZXN0aW5hdGlvbj0i\
    aHR0cHM6Ly9sb2dpbi5taWNyb3NvZnRvbmxpbmUuY29tL2NvbW1vbi9zYW1sMiIgQXNzZXJ0aW9u\
    Q29uc3VtZXJTZXJ2aWNlVVJMPSJodHRwczovL2FwcC5leGFtcGxlLmNvbS9zc28vYWNzIiBQcm90\
    b2NvbEJpbmRpbmc9InVybjpvYXNpczpuYW1lczp0YzpTQU1MOjIuMDpiaW5kaW5nczpIVFRQLVBP\
    U1QiPjxzYW1sOklzc3Vlcj5odHRwczovL2FwcC5leGFtcGxlLmNvbS9zc28vbWV0YWRhdGE8L3Nh\
    bWw6SXNzdWVyPjxzYW1scDpOYW1lSURQb2xpY3kgRm9ybWF0PSJ1cm46b2FzaXM6bmFtZXM6dGM6\
    U0FNTDoyLjA6bmFtZWlkLWZvcm1hdDpwZXJzaXN0ZW50IiBBbGxvd0NyZWF0ZT0idHJ1ZSIvPjwv\
    c2FtbHA6QXV0aG5SZXF1ZXN0Pg==
    """

  /// An AuthnRequest with no `AssertionConsumerServiceURL`, so the issuer is all there
  /// is to derive a destination from.
  static let issuerOnly = """
    fZDBasMwDIZfJfje2AljMJEECr0U1ss2dthliMxrDbbkWgr08eemDLrLQELolz70o0EwxQzbRU/0\
    4s+LF20uKZLAOhjNUggYJQgQJi+gM7xuD8/Qtw5yYeWZo7lD/idQxBcNTKbZ70bziZ1p3n2Rqoym\
    LlRZZPF7EkXSKrn+ceOeNt3DW9eDczU+TLOrLgOhrtRJNQtYG/kYqE1hLiz8rUwxkG9nTrZmYrJX\
    d72ZhmuF9UyZfmHMufUXTDneEBG2ySt+oeJg74lb9/dj0w8=
    """

  /// An AuthnRequest whose issuer is a URN, which is nothing to show a user.
  static let urnIssuer = """
    fVDBasMwDP2V4Htj14zBRBIo9FLYLtvYYZdhMnU12JJnKdDPn5NdustAQujpPemhQUJOBQ6LXugZ\
    vxcU7a45kcA2GM1SCThIFKCQUUBneDk8PYLvHZTKyjMncyP5XxFEsGpkMt3pOJqP4E33hlUaMppG\
    aLDIgicSDaQNcv5+5x52+7vXvQfnWryb7thcRgq6qS6qRcDaxF+R+hznysJnZUqRsJ8525aZya7u\
    vJmGtcJ2pk6r1zN+Yt2WAV5DLgkhlDLYW95v9/dP0w8=
    """
}
