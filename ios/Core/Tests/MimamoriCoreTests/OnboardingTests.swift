import Foundation
import Testing

@testable import MimamoriCore

/// The balloons that show what a button does, the first time each screen opens. The author asked to
/// see two samples side by side (TipKit and a coach mark of our own) on 2026-11-07; both share these
/// words and this order.
@Suite("ボタンの吹き出し")
struct OnboardingTests {
  @Test("母の画面は笑顔、話しかける、写真の順")
  func protectedOrder() {
    #expect(OnboardingStep.steps(for: .protected) == [.smile, .talk, .photo])
  }

  @Test("家族の画面は招待、電話する、解決の順")
  func familyOrder() {
    #expect(OnboardingStep.steps(for: .family) == [.invite, .call, .resolve])
  }

  @Test("作者が決めた母の画面の文言")
  func protectedWords() {
    #expect(OnboardingStep.smile.words == "笑顔を家族に届ける")
    #expect(OnboardingStep.talk.words == "困ったら話しかけてね")
    #expect(OnboardingStep.photo.words == "画面の写真で聞ける")
  }

  @Test("吹き出しは12字まで、読点のつなぎも、です・ますも無い", arguments: OnboardingStep.allCases)
  func wordsAreShort(step: OnboardingStep) {
    #expect(step.words.count <= 12)
    #expect(!step.words.contains("、"))
    #expect(!step.words.hasSuffix("です"))
    #expect(!step.words.hasSuffix("ます"))
  }

  @Test("VoiceOver には画面の文字より長い説明が残る", arguments: OnboardingStep.allCases)
  func spokenIsLonger(step: OnboardingStep) {
    #expect(step.spoken.count > step.words.count)
  }

  @Test("起動の引数で見本を選ぶ。無いか知らない値なら出さない")
  func style() {
    #expect(OnboardingStyle(arguments: ["app", "-mimamori-onboarding", "tipkit"]) == .tipKit)
    #expect(OnboardingStyle(arguments: ["app", "-mimamori-onboarding", "spotlight"]) == .spotlight)
    #expect(OnboardingStyle(arguments: ["app", "-mimamori-onboarding", "other"]) == nil)
    #expect(OnboardingStyle(arguments: ["app", "-mimamori-onboarding"]) == nil)
    #expect(OnboardingStyle(arguments: ["app"]) == nil)
  }

  @Test("照らす見本は1/3から始まり、次へで進み、最後の次へで終わる")
  func tour() {
    var tour = CoachMarkTour(role: .protected)
    #expect(tour.current == .smile)
    #expect(tour.progress == "1/3")
    #expect(!tour.isLast)
    tour.next()
    #expect(tour.current == .talk)
    #expect(tour.progress == "2/3")
    tour.next()
    #expect(tour.current == .photo)
    #expect(tour.isLast)
    tour.next()
    #expect(tour.current == nil)
    #expect(tour.progress == nil)
    tour.next()
    #expect(tour.current == nil)
  }

  @Test("閉じると残りを飛ばして終わる")
  func close() {
    var tour = CoachMarkTour(role: .family)
    tour.close()
    #expect(tour.current == nil)
  }
}
