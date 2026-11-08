import Foundation
import Testing

@testable import MimamoriCore

/// The balloons that say what a button is for, the first time each home screen opens (#283). The
/// author chose the coach mark (dark screen, one lit button, "次へ") on 2026-11-08.
@Suite("ボタンの吹き出し")
struct OnboardingTests {
  @Test("母の画面は笑顔、話しかける、写真の順")
  func protectedOrder() {
    #expect(OnboardingStep.steps(for: .protected, hasCards: false) == [.smile, .talk, .photo])
    #expect(OnboardingStep.steps(for: .protected, hasCards: true) == [.smile, .talk, .photo])
  }

  @Test("家族の画面はカードがあれば招待、笑顔、設定、電話する、解決の順")
  func familyOrderWithCards() {
    #expect(
      OnboardingStep.steps(for: .family, hasCards: true)
        == [.invite, .familySmile, .settings, .call, .resolve])
  }

  @Test("カードの無い家族の画面では電話と解決を飛ばす")
  func familyOrderWithoutCards() {
    #expect(
      OnboardingStep.steps(for: .family, hasCards: false) == [.invite, .familySmile, .settings])
  }

  @Test("作者が決めた母の画面の文")
  func protectedWords() {
    #expect(OnboardingStep.smile.words == "ここで笑顔を撮って家族に届けてね")
    #expect(OnboardingStep.talk.words == "困ったことはここで話しかけてね")
    #expect(OnboardingStep.photo.words == "気になる画面の写真はここから送ってね")
  }

  @Test("作者が決めた家族の画面の文")
  func familyWords() {
    #expect(OnboardingStep.invite.words == "ここでコードを作ってほかの家族を呼んでね")
    #expect(OnboardingStep.familySmile.words == "ここで母の笑顔を見て笑顔を返してね")
    #expect(OnboardingStep.settings.words == "ここで笑顔の知らせと時刻を決めてね")
    #expect(OnboardingStep.call.words == "心配なときはここから母に電話してね")
    #expect(OnboardingStep.resolve.words == "問題なさそうならここで解決してね")
  }

  @Test("語尾は「〜してね」にそろえ、読点のつなぎは入れない", arguments: OnboardingStep.allCases)
  func wordsEndAlike(step: OnboardingStep) {
    // 「呼んでね」 is the same ending, voiced.
    #expect(step.words.hasSuffix("てね") || step.words.hasSuffix("んでね"))
    #expect(!step.words.contains("、"))
  }

  @Test("解決は電話と結びつけない")
  func resolveIsNotTiedToCalling() {
    for text in [OnboardingStep.resolve.words, OnboardingStep.resolve.spoken] {
      #expect(!text.contains("話せたら"))
      #expect(!text.contains("話して"))
      #expect(!text.contains("電話"))
    }
  }

  @Test("VoiceOver には画面の文字より長い説明が残る", arguments: OnboardingStep.allCases)
  func spokenIsLonger(step: OnboardingStep) {
    #expect(step.spoken.count > step.words.count)
  }

  @Test("照らす見本は1/3から始まり、次へで進み、最後の次へで終わる")
  func tour() {
    var tour = CoachMarkTour(steps: OnboardingStep.steps(for: .protected, hasCards: false))
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
    var tour = CoachMarkTour(steps: OnboardingStep.steps(for: .family, hasCards: true))
    tour.close()
    #expect(tour.current == nil)
  }

  @Test("一度出したら次からは出ない。役ごとに覚える")
  func onlyOnce() {
    let record = OnboardingRecord(store: InMemoryOnboardingStore())
    let first = record.tourIfFirst(role: .family, hasCards: false)
    #expect(first?.steps == [.invite, .familySmile, .settings])
    #expect(record.tourIfFirst(role: .family, hasCards: true) == nil)
    #expect(record.tourIfFirst(role: .protected, hasCards: false)?.current == .smile)
    #expect(record.tourIfFirst(role: .protected, hasCards: false) == nil)
  }

  @Test("見た記録は端末の置き場から読み直しても残る")
  func remembersAcrossLaunches() {
    let store = InMemoryOnboardingStore()
    _ = OnboardingRecord(store: store).tourIfFirst(role: .protected, hasCards: false)
    #expect(OnboardingRecord(store: store).tourIfFirst(role: .protected, hasCards: false) == nil)
  }

  @Test("すべて消すと記録も消え、また最初の一度が出る")
  func forget() {
    let record = OnboardingRecord(store: InMemoryOnboardingStore())
    _ = record.tourIfFirst(role: .family, hasCards: false)
    record.forget()
    #expect(record.tourIfFirst(role: .family, hasCards: false) != nil)
  }

  @Test("スクショ用に出し直すときは記録を見ず、記録も残さない")
  func forced() {
    let store = InMemoryOnboardingStore()
    let record = OnboardingRecord(store: store)
    #expect(record.tourIfFirst(role: .family, hasCards: true, force: true) != nil)
    #expect(record.tourIfFirst(role: .family, hasCards: true, force: true) != nil)
    #expect(record.tourIfFirst(role: .family, hasCards: true) != nil)
  }
}
