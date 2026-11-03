import Foundation
import Testing

@testable import MimamoriCore

@Suite("失敗の見せ方")
struct ProblemTests {
  @Test("入るときの 404(使い終わった、期限切れ、知らないコード)だけをコードの誤りとする")
  func onlyJoin404IsBadCode() {
    #expect(Problem(APIError.http(status: 404), joining: true) == .badCode)
    #expect(Problem(APIError.http(status: 400), joining: true) == .unreachable)
    #expect(Problem(APIError.http(status: 404), joining: false) == .unreachable)
    #expect(Problem(APIError.http(status: 500), joining: true) == .unreachable)
    #expect(Problem(URLError(.notConnectedToInternet), joining: true) == .unreachable)
  }

  @Test("401 は画面の切り替えで伝えるので、知らせを出さない")
  func unauthorizedHasNoProblem() {
    #expect(Problem(APIError.unauthorized, joining: false) == nil)
    #expect(Problem(APIError.unauthorized, joining: true) == nil)
  }
}
