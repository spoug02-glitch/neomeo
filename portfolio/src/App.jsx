import { useEffect, useRef, useState } from 'react'

/* ══════════════════════════════════════════════════
   유틸리티 컴포넌트
══════════════════════════════════════════════════ */

function FadeUp({ children, delay = 0 }) {
  const ref = useRef(null)
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const obs = new IntersectionObserver(
      ([e]) => { if (e.isIntersecting) { setVisible(true); obs.disconnect() } },
      { threshold: 0.08 }
    )
    obs.observe(el)
    return () => obs.disconnect()
  }, [])
  return (
    <div
      ref={ref}
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? 'translateY(0)' : 'translateY(30px)',
        transition: `opacity 0.7s ease ${delay}ms, transform 0.7s ease ${delay}ms`,
      }}
    >
      {children}
    </div>
  )
}

function SectionLabel({ children, light = false }) {
  return (
    <p className={`text-sm font-bold tracking-[0.25em] uppercase mb-4 ${light ? 'text-primary-300' : 'text-primary-500'}`}>
      {children}
    </p>
  )
}

/* ══════════════════════════════════════════════════
   폰 프레임 (실제 이미지용)
══════════════════════════════════════════════════ */

function PhoneFrame({ src, alt, large = false }) {
  return (
    <div style={{
      width: large ? 200 : 170,
      borderRadius: 36,
      border: '6px solid #1e1e1e',
      boxShadow: '0 0 0 1px #2a2a2a, 0 28px 64px rgba(0,0,0,.85)',
      overflow: 'hidden',
      flexShrink: 0,
      background: '#111',
    }}>
      <img
        src={src}
        alt={alt}
        style={{ width: '100%', display: 'block' }}
      />
    </div>
  )
}

/* ══════════════════════════════════════════════════
   메인 APP
══════════════════════════════════════════════════ */

export default function App() {
  return (
    <div className="min-h-screen bg-white" style={{ fontFamily: '"Pretendard", "Noto Sans KR", system-ui, sans-serif' }}>

      {/* ══════════════════════
          1. HERO
      ══════════════════════ */}
      <section style={{ background: 'linear-gradient(160deg, #0e0945 0%, #1a1270 50%, #0e0945 100%)', overflow: 'hidden' }}>
        <div className="max-w-[1000px] mx-auto px-8 pt-20 pb-0">

          <FadeUp>
            <div className="flex items-center gap-3 mb-8">
              <span className="text-sm font-bold tracking-[0.3em] uppercase text-primary-400">UX Portfolio</span>
              <span className="w-1 h-1 rounded-full bg-primary-700 inline-block" />
              <span className="text-sm font-bold tracking-[0.3em] uppercase text-primary-500">행동 개입 시스템</span>
            </div>
          </FadeUp>

          <FadeUp delay={80}>
            <h1 className="text-[8rem] leading-none font-black tracking-tight text-white mb-4" style={{ letterSpacing: '-4px' }}>
              너머
            </h1>
          </FadeUp>

          <FadeUp delay={160}>
            <p className="text-primary-200 text-lg font-light mb-2">
              행동 개입 기반 외출 보조 시스템
            </p>
            <p className="text-primary-500 text-sm mb-20">
              기억이 아니라 상황이 행동을 만든다
            </p>
          </FadeUp>

          {/* 온보딩 3화면 */}
          <FadeUp delay={240}>
            <div className="flex items-end justify-center gap-6 relative">
              {/* 글로우 */}
              <div className="absolute -inset-8 blur-3xl rounded-3xl" style={{ background: 'radial-gradient(ellipse, rgba(108,82,245,.25) 0%, transparent 70%)' }} />

              <div className="relative" style={{ transform: 'translateY(20px) rotate(-4deg)', transformOrigin: 'bottom center' }}>
                <PhoneFrame src="/onboard2.jpg" alt="알람 권한 온보딩" />
              </div>
              <div className="relative" style={{ transform: 'translateY(0px)', zIndex: 2 }}>
                <PhoneFrame src="/onboard1.jpg" alt="위치 권한 온보딩" large />
              </div>
              <div className="relative" style={{ transform: 'translateY(20px) rotate(4deg)', transformOrigin: 'bottom center' }}>
                <PhoneFrame src="/onboard3.jpg" alt="집 위치 설정 온보딩" />
              </div>
            </div>
          </FadeUp>
        </div>
      </section>

      {/* ══════════════════════
          2. 문제 정의
      ══════════════════════ */}
      <section className="py-32 px-8 bg-white">
        <div className="max-w-[1000px] mx-auto">

          <FadeUp>
            <SectionLabel>Problem Definition</SectionLabel>
            <h2 className="text-5xl font-black leading-tight mb-3 text-gray-900">
              UXUI 학원에서<br />발견한 페인포인트
            </h2>
            <p className="text-gray-400 text-lg font-light mb-14">
              국민내일배움카드를 찍어야 하는데 — 수강생 20명이 매번 놓쳤다
            </p>
          </FadeUp>

          {/* 동기 스토리 */}
          <FadeUp delay={80}>
            <div className="rounded-2xl border-2 border-gray-100 bg-gray-50 p-8 mb-6">
              <div className="text-sm font-bold tracking-widest uppercase text-gray-400 mb-6">Motivation Story</div>
              <div className="grid grid-cols-3 gap-6">
                <div className="flex flex-col gap-3">
                  <div className="w-10 h-10 rounded-xl bg-blue-100 flex items-center justify-center text-xl">🏫</div>
                  <p className="font-bold text-gray-800 text-sm">등교 · 하교 시 카드 태깅 필수</p>
                  <p className="text-gray-500 text-sm leading-snug">UXUI 포트폴리오 학원은 등교할 때, 하교할 때 국민내일배움카드를 단말기에 찍어야 한다</p>
                </div>
                <div className="flex flex-col gap-3">
                  <div className="w-10 h-10 rounded-xl bg-red-100 flex items-center justify-center text-xl">😩</div>
                  <p className="font-bold text-gray-800 text-sm">수강생 20명이 반복적으로 누락</p>
                  <p className="text-gray-500 text-sm leading-snug">매번 잊고 지나쳐, 학원 단체 공지방에 "카드 안 찍으신 분들 확인해주세요" 공지가 빈번하게 올라왔다</p>
                </div>
                <div className="flex flex-col gap-3">
                  <div className="w-10 h-10 rounded-xl bg-primary-100 flex items-center justify-center text-xl">💡</div>
                  <p className="font-bold text-gray-800 text-sm">페인포인트 → 아이디어</p>
                  <p className="text-gray-500 text-sm leading-snug">학원에 들어올 때 / 나갈 때, <strong>위치 기반으로 '국민내일배움카드를 찍으세요' 체크리스트가 자동으로 뜬다면?</strong></p>
                </div>
              </div>
            </div>
          </FadeUp>

          {/* 3열 문제 카드 */}
          <FadeUp delay={160}>
            <div className="grid grid-cols-3 gap-4 mb-10">
              {[
                {
                  icon: '😫',
                  title: '발견한 문제',
                  color: 'border-red-200 bg-red-50',
                  badge: 'bg-red-100 text-red-600',
                  items: ['등교·하교 시 카드 태깅 누락', '20명 수강생의 반복 실수', '단체 공지방 공지가 빈번히 올라옴'],
                },
                {
                  icon: '⚡',
                  title: '기존 방식의 한계',
                  color: 'border-orange-200 bg-orange-50',
                  badge: 'bg-orange-100 text-orange-600',
                  items: ['구두 공지는 그 순간만 기억됨', '개인 메모·알람은 설정 자체를 잊음', '자율에 맡기면 무시율 높음'],
                },
                {
                  icon: '🗺️',
                  title: '확장 가능성',
                  color: 'border-gray-200 bg-gray-50',
                  badge: 'bg-gray-100 text-gray-600',
                  items: ['장소마다 다른 체크리스트 필요', '외출 준비물도 같은 구조로 해결 가능', '위치 기반 자동화로 누락 제로 목표'],
                },
              ].map(({ icon, title, color, badge, items }) => (
                <div key={title} className={`rounded-2xl border-2 p-7 ${color}`}>
                  <div className={`inline-flex items-center gap-1.5 text-sm font-bold px-3 py-1 rounded-full mb-5 ${badge}`}>
                    {icon} {title}
                  </div>
                  <div className="space-y-3">
                    {items.map(item => (
                      <div key={item} className="flex items-start gap-2">
                        <span className="text-gray-300 mt-0.5 text-sm">—</span>
                        <span className="text-gray-600 text-sm leading-snug">{item}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </FadeUp>

          {/* 핵심 메시지 배너 */}
          <FadeUp delay={240}>
            <div className="flex items-center gap-5 bg-gray-950 rounded-2xl px-8 py-7">
              <div className="text-4xl">📍</div>
              <div>
                <p className="text-white font-black text-xl leading-snug">
                  상황이 바뀌는 그 순간 —<br />체크리스트가 자동으로 나타난다면
                </p>
                <p className="text-gray-500 text-sm mt-2 font-light">
                  기억력의 문제가 아니라 — 시스템 설계의 문제
                </p>
              </div>
            </div>
          </FadeUp>
        </div>
      </section>

      {/* ══════════════════════
          3. 인사이트 & 해결 전략
      ══════════════════════ */}
      <section className="py-32 px-8" style={{ background: '#f5f4fe' }}>
        <div className="max-w-[1000px] mx-auto">

          <FadeUp>
            <SectionLabel>Insight & Strategy</SectionLabel>
            <h2 className="text-5xl font-black leading-tight mb-3 text-gray-900">
              기억이 아니라<br />상황이 행동을 만든다
            </h2>
            <p className="text-gray-500 text-lg font-light mb-14">
              인간의 기억력에 호소하는 대신, 상황이 행동을 강제하도록 설계한다
            </p>
          </FadeUp>

          {/* 흐름 배너 */}
          <FadeUp delay={80}>
            <div className="flex items-center gap-3 mb-14 flex-wrap">
              {[
                { label: '기억 의존', icon: '🧠', desc: '실패', dim: true },
                null,
                { label: '상황(Context)', icon: '📍', desc: '개입' },
                null,
                { label: '행동 강제', icon: '🔒', desc: '성공' },
              ].map((item, i) =>
                item === null ? (
                  <div key={i} className="text-primary-300 text-2xl font-light">→</div>
                ) : (
                  <div
                    key={i}
                    className={`flex items-center gap-2 rounded-xl px-5 py-3 text-sm font-semibold ${
                      item.dim
                        ? 'bg-gray-100 text-gray-400 line-through decoration-red-300'
                        : 'bg-primary-600 text-white shadow-lg shadow-primary-200'
                    }`}
                  >
                    <span>{item.icon}</span>
                    <span>{item.label}</span>
                    <span className={`text-sm px-2 py-0.5 rounded-full font-normal ${
                      item.dim ? 'bg-gray-200 text-gray-400' : 'bg-primary-500 text-primary-100'
                    }`}>
                      {item.desc}
                    </span>
                  </div>
                )
              )}
            </div>
          </FadeUp>

          {/* 인사이트 + 해결 방향 2열 */}
          <FadeUp delay={160}>
            <div className="grid grid-cols-2 gap-6 mb-10">
              {/* 핵심 인사이트 */}
              <div className="rounded-2xl border-2 border-primary-200 bg-white p-8">
                <div className="text-sm font-bold tracking-widest uppercase text-primary-500 mb-5">핵심 인사이트</div>
                <div className="space-y-5">
                  {[
                    { icon: '📍', text: '장소 진입·이탈 시점이 가장 효과적인 개입 타이밍' },
                    { icon: '🚧', text: '행동 게이트(강제 중단)를 두면 실수 급감' },
                    { icon: '📈', text: '카드 태깅처럼 \'장소에서만 필요한 행동\'은 위치가 트리거가 되어야 한다' },
                  ].map(({ icon, text }) => (
                    <div key={text} className="flex items-start gap-3">
                      <span className="text-xl mt-0.5">{icon}</span>
                      <p className="text-gray-700 text-sm leading-snug font-medium">{text}</p>
                    </div>
                  ))}
                </div>
              </div>

              {/* 해결 방향 */}
              <div className="rounded-2xl border-2 border-primary-600 bg-primary-950 p-8">
                <div className="text-sm font-bold tracking-widest uppercase text-primary-400 mb-5">해결 방향</div>
                <div className="space-y-4">
                  {[
                    ['📍', '지오펜스로 외출 감지 → 정확한 타이밍'],
                    ['🔒', '체크 완료 전 출발 차단 → 강제 준수'],
                    ['☁️', '날씨·장소 기반 준비물 추천 → 상황 반영'],
                    ['⏰', '알림 시점 커스터마이즈 → 경보 피로 최소화'],
                  ].map(([icon, text]) => (
                    <div key={text} className="flex items-start gap-3">
                      <span className="text-base">{icon}</span>
                      <p className="text-primary-200 text-sm leading-snug">{text}</p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </FadeUp>

          {/* 서비스 컨셉 배너 */}
          <FadeUp delay={240}>
            <div className="rounded-2xl bg-primary-600 p-8 text-center shadow-2xl shadow-primary-200">
              <p className="text-white font-black text-2xl leading-snug">
                외출 실수를 구조적으로 차단하는<br />컨텍스트 체크리스트
              </p>
              <p className="text-primary-200 text-sm mt-3 font-light">
                "기억이 아니라 상황이 행동을 만든다" — 의지력이 아닌 설계로 해결
              </p>
            </div>
          </FadeUp>
        </div>
      </section>

      {/* ══════════════════════
          4. 구조 & 시스템
      ══════════════════════ */}
      <section className="py-32 px-8 bg-white">
        <div className="max-w-[1000px] mx-auto">

          <FadeUp>
            <SectionLabel>Structure & System</SectionLabel>
            <h2 className="text-5xl font-black leading-tight mb-3 text-gray-900">
              상황이<br />자동으로 개입한다
            </h2>
            <p className="text-gray-400 text-lg font-light mb-14">
              지오펜스 · 날씨 · 장소 컨텍스트 → 체크리스트 트리거 → 게이트 통과
            </p>
          </FadeUp>

          {/* 서비스 구조 흐름 */}
          <FadeUp delay={100}>
            <div className="grid grid-cols-3 gap-4 mb-14">
              {[
                { step: '01', icon: '📍', title: '지오펜스 감지', sub: '현관 통과 자동 인식', color: 'bg-blue-50 border-blue-200 text-blue-600' },
                { step: '02', icon: '🌦️', title: '맥락 분석', sub: '날씨 · 목적지 반영', color: 'bg-violet-50 border-violet-200 text-violet-600' },
                { step: '03', icon: '🔒', title: '출발 게이트', sub: '미확인 시 출발 차단', color: 'bg-primary-50 border-primary-200 text-primary-600' },
              ].map(({ step, icon, title, sub, color }, i) => (
                <div key={i} className="relative">
                  {i < 2 && (
                    <div className="absolute top-1/2 -right-5 -translate-y-1/2 z-10 text-gray-300 text-xl">→</div>
                  )}
                  <div className={`rounded-2xl border-2 p-7 ${color.split(' ')[0]} ${color.split(' ')[1]}`}>
                    <div className={`inline-flex text-sm font-bold px-2.5 py-1 rounded-full mb-5 ${color.split(' ')[0]} ${color.split(' ')[2]} border ${color.split(' ')[1]}`}>
                      STEP {step}
                    </div>
                    <div className="text-4xl mb-3">{icon}</div>
                    <p className="font-bold text-gray-800 text-sm mb-1">{title}</p>
                    <p className="text-gray-400 text-sm">{sub}</p>
                  </div>
                </div>
              ))}
            </div>
          </FadeUp>

          {/* 핵심 기능 카드 */}
          <FadeUp delay={160}>
            <div className="grid grid-cols-2 gap-4 mb-8">
              {[
                { icon: '📍', title: '지오펜스 기반 외출 감지', why: '타이밍 자동화, 알림 낭비 감소', badge: '트리거', bc: 'bg-blue-100 text-blue-700' },
                { icon: '☁️', title: '날씨 기반 준비물 자동 추천', why: '비·추위 등 변수 자동 반영', badge: '컨텍스트', bc: 'bg-violet-100 text-violet-700' },
                { icon: '🔒', title: '체크 완료 시에만 출발 가능', why: '미루기·무시를 구조적으로 차단', badge: '게이트', bc: 'bg-green-100 text-green-700' },
                { icon: '🗺️', title: '장소별 체크리스트', why: '맥락별 항목 자동 로딩, 누락 감소', badge: '맞춤화', bc: 'bg-orange-100 text-orange-700' },
              ].map(({ icon, title, why, badge, bc }) => (
                <div key={title} className="bg-gray-50 rounded-2xl border border-gray-100 p-6 flex gap-4">
                  <div className="text-3xl mt-0.5">{icon}</div>
                  <div className="flex-1">
                    <div className="flex items-start justify-between gap-3 mb-2">
                      <p className="font-bold text-gray-800 text-sm leading-snug">{title}</p>
                      <span className={`text-sm font-bold px-2.5 py-1 rounded-full shrink-0 ${bc}`}>{badge}</span>
                    </div>
                    <p className="text-gray-400 text-sm leading-snug">{why}</p>
                  </div>
                </div>
              ))}
            </div>
          </FadeUp>

          {/* 차별화 포인트 3개 */}
          <FadeUp delay={240}>
            <div className="grid grid-cols-3 gap-4">
              {[
                { from: '수동 체크리스트', to: '자동 트리거 + 게이트', icon: '⚡' },
                { from: '오탐·누락 발생', to: '컨텍스트 인식으로 감소', icon: '🎯' },
                { from: '기억 보조', to: '행동 제어', icon: '🔒' },
              ].map(({ from, to, icon }) => (
                <div key={from} className="bg-primary-950 rounded-2xl p-6 text-center">
                  <div className="text-3xl mb-4">{icon}</div>
                  <p className="text-gray-600 text-sm line-through mb-2">{from}</p>
                  <div className="w-6 h-px bg-primary-700 mx-auto mb-2" />
                  <p className="text-primary-300 text-sm font-bold">{to}</p>
                </div>
              ))}
            </div>
          </FadeUp>
        </div>
      </section>

      {/* ══════════════════════
          5. 실제 앱 화면
      ══════════════════════ */}
      <section className="py-32 px-8" style={{ background: '#0e0945' }}>
        <div className="max-w-[1000px] mx-auto">

          <FadeUp>
            <SectionLabel light>Usage Flow</SectionLabel>
            <h2 className="text-5xl font-black leading-tight mb-3 text-white">
              사용자는<br />아무것도 시작하지 않는다
            </h2>
            <p className="text-primary-400 text-lg font-light mb-20">
              시스템이 상황을 읽고, 먼저 개입한다
            </p>
          </FadeUp>

          {/* 스텝 레이블 */}
          <div className="grid grid-cols-3 gap-6 mb-10">
            {[
              { step: '01', label: '외출', sub: 'TRIGGER', icon: '🚪' },
              { step: '02', label: '자동 개입', sub: 'CONTEXT', icon: '🔔' },
              { step: '03', label: '출발 게이트', sub: 'GATE', icon: '✅' },
            ].map(({ step, label, sub, icon }, i) => (
              <FadeUp key={i} delay={i * 80}>
                <div className="text-center mb-4">
                  <div className="text-sm font-mono text-primary-500 tracking-widest mb-1">{sub}</div>
                  <div className="text-white font-bold text-lg">{icon} {label}</div>
                </div>
              </FadeUp>
            ))}
          </div>

          {/* 3개 폰 화면 */}
          <FadeUp delay={200}>
            <div className="flex items-center justify-center gap-6 relative">
              <div className="absolute -inset-6 blur-3xl rounded-3xl" style={{ background: 'radial-gradient(ellipse, rgba(108,82,245,.2) 0%, transparent 70%)' }} />

              <div className="relative">
                <PhoneFrame src="/flow1.jpg" alt="홈 화면" large />
              </div>

              <div className="text-primary-700 text-2xl font-light">→</div>

              <div className="relative" style={{ zIndex: 2 }}>
                <PhoneFrame src="/flow2.jpg" alt="체크리스트 진행 중" large />
              </div>

              <div className="text-primary-700 text-2xl font-light">→</div>

              <div className="relative">
                <PhoneFrame src="/flow3.jpg" alt="체크 완료 출발" large />
              </div>
            </div>
          </FadeUp>

          {/* 부연 흐름 */}
          <FadeUp delay={300}>
            <div className="mt-14 grid grid-cols-3 gap-4">
              {[
                ['현관문을 나서는 순간 지오펜스가 자동 감지', 'text-primary-300'],
                ['날씨·목적지 기반으로 맞춤 체크리스트 생성', 'text-primary-300'],
                ['모든 항목 확인 전 출발 버튼 비활성화', 'text-green-400'],
              ].map(([text, col], i) => (
                <div key={i} className="bg-white/5 rounded-xl p-5 border border-white/10">
                  <p className={`text-sm font-medium leading-snug ${col}`}>{text}</p>
                </div>
              ))}
            </div>
          </FadeUp>
        </div>
      </section>

      {/* ══════════════════════
          6. 차별화
      ══════════════════════ */}
      <section className="py-32 px-8 bg-white">
        <div className="max-w-[1000px] mx-auto">

          <FadeUp>
            <SectionLabel>Differentiation</SectionLabel>
            <h2 className="text-5xl font-black leading-tight mb-3 text-gray-900">
              수동 체크리스트 vs<br />자동 개입 시스템
            </h2>
            <p className="text-gray-400 text-lg font-light mb-14">
              의지력에 의존하는 설계 vs 상황이 행동을 강제하는 설계
            </p>
          </FadeUp>

          <FadeUp delay={120}>
            <div className="grid grid-cols-2 gap-6 mb-10">

              {/* 기존 방식 */}
              <div className="rounded-2xl border-2 border-gray-200 p-8 bg-gray-50">
                <div className="text-sm font-bold tracking-widest uppercase text-gray-400 mb-6">기존 체크리스트</div>
                <div className="divide-y divide-gray-100">
                  {[
                    '앱을 직접 열어야 동작',
                    '고정 시간 알림 — 맥락 무관',
                    '확인을 강제하는 수단 없음',
                    '기억에 전적으로 의존',
                    '날씨 · 목적지 반영 불가',
                  ].map(item => (
                    <div key={item} className="flex items-center gap-3 py-3.5">
                      <span className="w-5 h-5 flex items-center justify-center text-red-400 shrink-0 text-sm">✕</span>
                      <span className="text-gray-400 text-sm">{item}</span>
                    </div>
                  ))}
                </div>
              </div>

              {/* 너머 */}
              <div className="rounded-2xl border-2 border-primary-500 p-8 bg-primary-50 shadow-2xl shadow-primary-100 relative overflow-hidden">
                <div className="absolute top-5 right-5 bg-primary-600 text-white text-sm px-3 py-1 rounded-full font-bold">
                  너머
                </div>
                <div className="text-sm font-bold tracking-widest uppercase text-primary-700 mb-6">자동 개입 시스템</div>
                <div className="divide-y divide-primary-100">
                  {[
                    '현관 통과 시 자동 실행',
                    '날씨 · 목적지 기반 맞춤 알림',
                    '출발 게이트로 행동 강제',
                    '상황(Context)이 행동을 유도',
                    '사용자 개입 최소화',
                  ].map(item => (
                    <div key={item} className="flex items-center gap-3 py-3.5">
                      <span className="w-5 h-5 flex items-center justify-center text-primary-500 shrink-0 font-bold">✓</span>
                      <span className="text-primary-900 text-sm font-medium">{item}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </FadeUp>

          {/* 핵심 전환 포인트 */}
          <FadeUp delay={240}>
            <div className="grid grid-cols-3 gap-4">
              {[
                { from: '기억 의존', to: '상황 트리거', icon: '🔄', color: 'text-blue-600' },
                { from: '수동 확인', to: '자동 감지', icon: '⚡', color: 'text-violet-600' },
                { from: '단순 메모', to: '행동 게이트', icon: '🔒', color: 'text-primary-600' },
              ].map(({ from, to, icon, color }) => (
                <div key={from} className="bg-gray-50 rounded-2xl p-6 text-center border border-gray-100">
                  <div className="text-3xl mb-4">{icon}</div>
                  <p className="text-gray-300 text-sm line-through mb-2">{from}</p>
                  <p className={`text-sm font-bold ${color}`}>{to}</p>
                </div>
              ))}
            </div>
          </FadeUp>
        </div>
      </section>

      {/* ══════════════════════
          FOOTER
      ══════════════════════ */}
      <footer style={{ background: '#0e0945' }} className="py-16 px-8 text-center">
        <div className="max-w-[1000px] mx-auto">
          <p className="text-white font-black text-6xl mb-3 tracking-tight" style={{ letterSpacing: '-3px' }}>너머</p>
          <p className="text-primary-400 text-sm font-light">행동 개입 기반 외출 보조 시스템 · UX Portfolio</p>
          <div className="mt-10 pt-10 border-t border-primary-900 flex justify-center flex-wrap gap-6 text-sm text-primary-700">
            <span>Problem Definition</span>
            <span>·</span>
            <span>Insight & Strategy</span>
            <span>·</span>
            <span>Structure & System</span>
            <span>·</span>
            <span>Usage Flow</span>
            <span>·</span>
            <span>Differentiation</span>
          </div>
        </div>
      </footer>

    </div>
  )
}
