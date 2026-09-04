import Foundation

/// 설정의 "문제점 알리기" — GitHub의 새 이슈 작성 화면을 연다.
/// 앱은 이슈를 직접 제출하지 않는다 — 제목과 본문을 채운 URL을 브라우저에 넘길 뿐이다.
enum SupportIssue {
    static let repository = "sacrezm/pokeforge"
    static let issuesNewURL = URL(string: "https://github.com/\(repository)/issues/new")!

    /// 새 이슈 URL 조립 — title/body는 URLComponents가 percent-encode한다.
    static func newIssueURL(title: String, body: String) -> URL? {
        var components = URLComponents(url: issuesNewURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents는 query의 '+'를 그대로 남길 수 있어, 브라우저가 공백으로 오독하지 않도록
        // query 부분의 '+'만 %2B로 치환한다(제목/본문의 'C++'·경로 등 왜곡 방지).
        guard let raw = components?.url?.absoluteString else { return nil }
        guard let q = raw.firstIndex(of: "?") else { return URL(string: raw) }
        let head = raw[...q]
        let query = raw[raw.index(after: q)...].replacingOccurrences(of: "+", with: "%2B")
        return URL(string: String(head) + query)
    }
}
