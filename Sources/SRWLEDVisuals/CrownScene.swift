import SwiftUI

/// Венец из колонн спектра, стоящих по кругу на наклонённой плоскости.
///
/// Объём здесь настоящий: круг колонн лежит в трёхмерном пространстве, наклонён
/// к зрителю и проецируется с делением на глубину. Отсюда всё сразу — ближние
/// колонны крупнее и ярче, дальние мельче и тонут; при вращении видно, как они
/// обходят друг друга. Каждая колонна рисуется не линией, а гранью с более светлой
/// вершиной, поэтому читается как тело, а не как штрих.
///
/// Композиция строго по центру своего блока: сцена ничего не знает про окно
/// и всегда стоит посередине того места, которое ей отдали.
public struct CrownScene: View {
    public typealias Sampler = () -> [Float]

    private let sampler: Sampler
    private let isRunning: Bool
    private let palette: Palette
    /// Свой тон вместо палитрового. Столбики — единственное, что человек
    /// правит на глаз прямо во время музыки, и ползунок тона под сценой
    /// обязан доходить до них, не проходя через набор готовых гамм.
    /// `nil` — брать тон из палитры.
    private let tint: Double?

    /// Тона сцены: свой, если задан. Свой тон разводится в вилку той же
    /// ширины, что и у палитры, — на одном тоне столбики теряют перепад
    /// между тихой и громкой полосой, на котором держится вся картинка.
    private var hues: (deep: Double, hot: Double) {
        guard let tint else { return palette.hues }
        return (tint - 0.037, tint + 0.038)
    }

    /// Время сцены, назначенное снаружи. В приложении всегда nil — время идёт
    /// от часов. Нужно превью: венец крутится, и два прогона подряд дают разный
    /// поворот, то есть разную картинку. Сравнивать кадры «до» и «после» правки
    /// при этом нельзя вовсе — разница между ними тонет в разнице поворота.
    private let frozenTime: TimeInterval?
    /// Лёгкое качество: половина частоты кадров и сцена без отражений.
    ///
    /// Не «плохо и быстро», а «то же самое, но дешевле»: убирается ровно то,
    /// что стоит дорого и читается тонко, — зеркало в настиле и половина
    /// кадров. Силуэт, цвет и движение остаются те же, и на глаз разница
    /// заметна не сразу.
    private let light: Bool

    @State private var smoother = SpectrumSmoother()
    @State private var beat = BeatFlash()

    public init(sampler: @escaping Sampler,
                isRunning: Bool,
                palette: Palette = .amber,
                tint: Double? = nil,
                frozenTime: TimeInterval? = nil,
                light: Bool = false)
    {
        self.sampler = sampler
        self.isRunning = isRunning
        self.palette = palette
        self.tint = tint
        self.frozenTime = frozenTime
        self.light = light
    }

    /// Колонн в венце. Много и тонких — так спектр читается подробно и аккуратно.
    private static let columns = 128

    public var body: some View {
        TimelineView(.animation(minimumInterval: light ? 1.0 / 30.0 : 1.0 / 60.0,
                                paused: !isRunning)) { timeline in
            let time = frozenTime ?? timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                beat.step(time: time, bass: smoother.values.prefix(3).max() ?? 0)
                drawBackdrop(&context, size: size, time: time)
                draw(&context, size: size, time: time)
                drawVignette(&context, size: size)
            }
        }
        // Ровное почти чёрное поле без градиента: любой градиент здесь читался
        // заливкой и спорил со сценой. Всё освещение даёт сама сцена.
        .background(Color(red: 0.019, green: 0.018, blue: 0.024))
    }

    /// Значение спектра по углу: зеркальная симметрия, чтобы венец читался
    /// как единая форма, а не как случайный частокол.
    private func spectrum(at position: Double) -> Double {
        let folded = position < 0.5 ? position * 2 : (1 - position) * 2
        let scaled = folded * 15
        let lower = min(15, Int(scaled))
        let upper = min(15, lower + 1)
        let blend = scaled - Double(lower)
        guard smoother.values.count == 16 else { return 0 }
        return smoother.values[lower] * (1 - blend) + smoother.values[upper] * blend
    }

    // MARK: - Фон
    //
    // Глубина фона берётся из планов, идущих с разной скоростью: дальняя дымка
    // почти стоит, средние контуры плывут еле заметно, ближние заметнее. Один
    // градиент, каким фон был раньше, глубины дать не может в принципе — глазу
    // не за что зацепиться.

    private func drawBackdrop(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let base = min(size.width, size.height)
        let hues = self.hues
        let energy = smoother.energy

        // Единственный источник в фоне — мягкий пул света под сценой.
        // Он даёт объекту опору и отделяет его от пустоты, но сам по себе
        // ничего не изображает: фон должен быть средой, а не картинкой.
        // Сильно сплюснутый эллипс: свет лежит НА плоскости, а круглое пятно
        // читалось висящей в воздухе кляксой. Сплющивание — сжатием холста:
        // круглый градиент в приплюснутом контуре обрывается сверху и снизу
        // на полусиле и даёт по полю шов.
        var pool = context
        pool.blendMode = .plusLighter
        let poolRadius = base * (0.46 + 0.07 * energy)
        let poolCentre = CGPoint(x: size.width / 2, y: size.height * 0.545)
        pool.translateBy(x: 0, y: poolCentre.y)
        pool.scaleBy(x: 1, y: 0.34)
        pool.translateBy(x: 0, y: -poolCentre.y)
        pool.fill(
            Path(ellipseIn: CGRect(x: poolCentre.x - poolRadius,
                                   y: poolCentre.y - poolRadius,
                                   width: poolRadius * 2, height: poolRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.85,
                                       brightness: 1).opacity(0.016 + 0.030 * energy), location: 0),
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.9,
                                       brightness: 1).opacity(0.005), location: 0.55),
                    .init(color: .clear, location: 1),
                ]),
                center: poolCentre, startRadius: 0, endRadius: poolRadius))
    }

    /// Затемнение по краям прижимает внимание к центру    /// Затемнение по краям прижимает внимание к центру и добавляет глубины.
    private func drawVignette(_ context: inout GraphicsContext, size: CGSize) {
        // Центр опущен ниже середины блока. Столбики растут вверх от пола,
        // и вся масса венца оказывается выше геометрического центра: замер
        // по кадру давал 95…800 при середине 506 — четыреста пикселей вверх
        // против трёхсот вниз. Композиция от этого читалась сползшей к верхней
        // кромке, хотя круг был построен ровно по центру.
        //
        // Сдвиг постоянный, а не по текущей высоте столбиков: плавающий
        // центр возил бы всю сцену вверх-вниз в такт музыке.
        let centre = CGPoint(x: size.width / 2,
                             y: size.height / 2 + min(size.width, size.height) * 0.052)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.34),
                    .init(color: .black.opacity(0.30), location: 0.78),
                    .init(color: .black.opacity(0.70), location: 1.0),
                ]),
                center: centre, startRadius: 0,
                endRadius: max(size.width, size.height) * 0.78))
    }

    /// То же, что spectrum, но по пиковым значениям.
    private func peakSpectrum(at position: Double) -> Double {
        let folded = position < 0.5 ? position * 2 : (1 - position) * 2
        let scaled = folded * 15
        let lower = min(15, Int(scaled))
        let upper = min(15, lower + 1)
        let blend = scaled - Double(lower)
        guard smoother.peaks.count == 16 else { return 0 }
        return smoother.peaks[lower] * (1 - blend) + smoother.peaks[upper] * blend
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Центр — строго середина отданного блока.
        // Центр опущен ниже середины блока. Столбики растут вверх от пола,
        // и вся масса венца оказывается выше геометрического центра: замер
        // по кадру давал 95…800 при середине 506 — четыреста пикселей вверх
        // против трёхсот вниз. Композиция от этого читалась сползшей к верхней
        // кромке, хотя круг был построен ровно по центру.
        //
        // Сдвиг постоянный, а не по текущей высоте столбиков: плавающий
        // центр возил бы всю сцену вверх-вниз в такт музыке.
        let centre = CGPoint(x: size.width / 2,
                             y: size.height / 2 + min(size.width, size.height) * 0.052)
        let base = min(size.width, size.height)
        let energy = smoother.energy
        let flash = beat.intensity
        let hues = self.hues

        // Венец крупнее прежнего. Композиция строится по короткой стороне кадра,
        // и при 0.325 сцена занимала меньше двух третей высоты — вокруг неё
        // оставалось поле пустоты шире самой сцены. Дальше поднимать нельзя:
        // на пике столбики подходят к верхней кромке кадра.
        let radius = base * 0.348
        let maxHeight = base * 0.313
        // Венец не крутится. Вращение раздражало ровно тем, ради чего его
        // и заводили: разметка ехала мимо, и чтобы прочитать, где какая
        // полоса, приходилось ждать, пока подпись подъедет. Неподвижное
        // кольцо читается как шкала прибора — глаз запоминает, где что.
        //
        // Развёрнут венец так, чтобы лицом к зрителю встала полоса 4479 Гц,
        // подписанная «4.5k». Угол считается, а не вписан числом: разметка
        // идёт по таблице полос прошивки, и стоит ей поменяться — поворот
        // приедет за ней сам. Прибавка в четверть оборота ставит нужный
        // угол в переднюю точку круга, там где глубина самая малая.
        // Ось симметрии венца — та, что проходит через самую нижнюю и самую
        // верхнюю полосу: спектр отражён, и правая половина кольца повторяет
        // левую именно относительно неё. Ось обязана лежать на вертикали
        // кадра, иначе картинка перекошена — а перекос в симметричной по
        // замыслу вещи глаз ловит мгновенно.
        //
        // Поэтому в переднюю точку ставится не отдельная полоса, а сама ось,
        // и 4479 Гц («4.5k») приходят к зрителю парой, по обе стороны от
        // середины в двенадцати градусах. Поставить одну полосу 4.5k строго
        // по центру нельзя, не свалив симметрию: через неё ось не проходит.
        // Бас при этом уходит за сцену, верх выходит вперёд — так и лучше:
        // самые высокие столбики стоят сзади и не заслоняют группу.
        let spin = 0.5 * 2 * .pi + .pi / 2
        let tilt = 0.92
        let focal = base * 2.0
        let distance = base * 2.1

        let cosSpin = cos(spin), sinSpin = sin(spin)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)
        let referenceScale = focal / distance

        /// Проекция без вращения: ею пользуются шкалы и сцена в центре.
        /// Группа музыкантов не должна кружиться вместе с венцом — иначе колонки
        /// разъезжаются по диагонали и раскладка теряет смысл.
        func projectStatic(_ x: Double, _ y: Double, _ z: Double)
            -> (CGPoint, Double, Double)
        {
            let ty = y * cosTilt - z * sinTilt
            let tz = y * sinTilt + z * cosTilt
            let scale = focal / max(tz + distance, 1)
            return (CGPoint(x: centre.x + x * scale, y: centre.y + ty * scale), scale, tz)
        }

        /// Проекция точки: экранные координаты, масштаб и глубина.
        func project(_ x: Double, _ y: Double, _ z: Double) -> (CGPoint, Double, Double) {
            let rx = x * cosSpin + z * sinSpin
            let rz = -x * sinSpin + z * cosSpin
            let ty = y * cosTilt - rz * sinTilt
            let tz = y * sinTilt + rz * cosTilt
            let scale = focal / max(tz + distance, 1)
            return (CGPoint(x: centre.x + rx * scale, y: centre.y + ty * scale), scale, tz)
        }

        // Свечение под венцом — только чтобы он не висел в пустоте.
        //
        // Сплющивается оно сжатием холста, а не сплющиванием контура. Круглый
        // градиент, залитый в приплюснутый эллипс, гаснет до нуля только по
        // горизонтали: сверху и снизу контур обрезает его на половине силы,
        // и по полю шёл видимый шов — овал с краем. На пробе яркости фона
        // это ступенька с 5 на 8 из 255, ровно по дуге эллипса. Пустота вокруг
        // сцены от такого шва перестаёт быть глубиной и становится кляксой,
        // подложенной под картинку.
        let glowRadius = radius * (1.5 + 0.25 * energy)
        var halo = context
        halo.blendMode = .plusLighter
        halo.translateBy(x: 0, y: centre.y)
        halo.scaleBy(x: 1, y: 0.5)
        halo.translateBy(x: 0, y: -centre.y)
        halo.fill(
            Path(ellipseIn: CGRect(x: centre.x - glowRadius, y: centre.y - glowRadius,
                                   width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.8,
                                       brightness: 1).opacity(0.07 + 0.12 * energy + 0.05 * flash),
                          location: 0),
                    .init(color: .clear, location: 1),
                ]),
                center: centre, startRadius: 0, endRadius: glowRadius))

        struct Lamp {
            var stem: Path
            var glass: Path
            var filament: Path
            var tip: CGPoint
            var tipSize: Double
            var peak: Path?
            var depth: Double
            var nearness: Double
            var facing: Double
            var value: Double
        }

        var lamps: [Lamp] = []
        lamps.reserveCapacity(Self.columns)

        let step = 2 * Double.pi / Double(Self.columns)
        let halfWidth = radius * step * 0.30

        // Колонна — цельная стеклянная трубка с нитью накаливания во всю длину,
        // как в филаментной лампе. Прошлый вариант делил столбик на стойку и колбу
        // сверху, и в нём нить жила только в верхней части — теперь она проходит
        // весь столбик и закреплена на обоих концах.
        for index in 0..<Self.columns {
            let position = Double(index) / Double(Self.columns)
            let theta = position * 2 * .pi
            let value = spectrum(at: position)
            let peakValue = peakSpectrum(at: position)
            let height = maxHeight * (0.05 + 0.95 * value)

            let tangentX = -sin(theta), tangentZ = cos(theta)
            let cx = cos(theta) * radius, cz = sin(theta) * radius
            let leftX = cx - tangentX * halfWidth, leftZ = cz - tangentZ * halfWidth
            let rightX = cx + tangentX * halfWidth, rightZ = cz + tangentZ * halfWidth

            let baseLeft = project(leftX, 0, leftZ)
            let baseRight = project(rightX, 0, rightZ)
            let topLeft = project(leftX, -height, leftZ)
            let topRight = project(rightX, -height, rightZ)
            let apex = project(cx, -height, cz)
            let foot = project(cx, 0, cz)

            // Стекло: трубка со скруглённой макушкой и скруглённым низом.
            let capRise = (baseLeft.0.y - topLeft.0.y) * 0.0
            _ = capRise
            let width = abs(baseRight.0.x - baseLeft.0.x)
            var glass = Path()
            glass.move(to: baseLeft.0)
            glass.addLine(to: topLeft.0)
            glass.addQuadCurve(to: topRight.0,
                               control: CGPoint(x: apex.0.x, y: apex.0.y - width * 0.85))
            glass.addLine(to: baseRight.0)
            glass.addQuadCurve(to: baseLeft.0,
                               control: CGPoint(x: foot.0.x, y: foot.0.y + width * 0.55))
            glass.closeSubpath()

            // Нить: по всей длине трубки, закреплена на обоих концах.
            var filament = Path()
            filament.move(to: project(cx, -height * 0.035, cz).0)
            filament.addLine(to: project(cx, -height * 0.965, cz).0)

            // Насколько трубка развёрнута лицом к камере. На боковых краях
            // круга касательная смотрит в глубину, и трубка сжимается на экране
            // почти в линию: там их набивается по десятку на два пикселя.
            // Ширина обводок при этом была назначена в долях кадра и не знала
            // про этот поворот — каждая боковая трубка мазала ореолом вчетверо
            // шире собственного тела, и сложение выжигало весь правый край
            // венца в сплошное белое пятно, в котором пропадали и трубки,
            // и шкала за ними. Множитель ниже возвращает ореолу его настоящий
            // размер: свет остаётся плотным, но перестаёт быть заливкой.
            let facing = min(1, width / max(0.001, 2 * halfWidth * baseLeft.1))

            var peak: Path?
            if peakValue > value + 0.04 {
                let peakY = maxHeight * (0.05 + 0.95 * peakValue)
                let markLeft = project(leftX * 1.22, -peakY, leftZ * 1.22)
                let markRight = project(rightX * 1.22, -peakY, rightZ * 1.22)
                var mark = Path()
                mark.move(to: markLeft.0)
                mark.addLine(to: markRight.0)
                peak = mark
            }

            lamps.append(Lamp(stem: Path(), glass: glass, filament: filament,
                              tip: apex.0,
                              tipSize: halfWidth * apex.1 * 0.55,
                              peak: peak,
                              depth: baseLeft.2,
                              nearness: baseLeft.1 / referenceScale,
                              facing: facing,
                              value: value))
        }

        lamps.sort { $0.depth > $1.depth }

        // Данные для лучей: макушка лампы, её накал, близость к зрителю и
        // разворот к камере. Последнее нужно по той же причине, что и самим
        // трубкам: на боковых краях круга их полсотни на пару десятков
        // пикселей, и полсотни лучей оттуда складываются в глухой веер.
        let beamSources = lamps.map {
            (point: $0.tip, value: $0.value,
             nearness: max(0.25, min(1, $0.nearness)) * (0.28 + 0.72 * $0.facing))
        }

        // Сцена стоит в центре, поэтому дальние лампы рисуются до неё, ближние —
        // после. Иначе передний ряд ламп окажется под фигурами.
        let stage = GlassStage(palette: palette,
                               reflects: !light,
                               hues: (hues.deep, hues.hot),
                               energy: energy,
                               bass: smoother.values.prefix(3).max() ?? 0,
                               air: smoother.values.suffix(4).max() ?? 0,
                               beat: flash,
                               time: time,
                               levels: smoother.values)
        var stageDrawn = false

        for lamp in lamps {
            if !stageDrawn && lamp.depth <= 0 {
                stage.draw(&context, project: projectStatic, radius: radius,
                           maxHeight: maxHeight, base: base)
                stageDrawn = true
            }

            // Спад в глубину. Прежняя вилка (0.72 и 0.55) укладывала весь
            // разброс близости, 0.91..1.11, в узкий отрезок 0.59..0.82:
            // дальняя дуга гасла всего на четверть и стояла вровень с ближней.
            // На сцене так не бывает — между дальним и ближним краем венца
            // добрая дюжина метров воздуха. Вилка сжата ровно по реальному
            // разбросу, и дальняя дуга уходит теперь втрое темнее ближней.
            let depthFade = max(0, min(1, (lamp.nearness - 0.90) / 0.21))
            // Скученность: на боковых краях круга трубки стоят на экране
            // впритык, и полная сила у каждой складывается в белую заливку.
            // Порог опущен ещё раз, уже по кадру: на левом и правом краю венца
            // пять нитей сливались в одну сплошную полосу с белёсой сердцевиной
            // шириной в дюжину пикселей — самое яркое и самое бесформенное место
            // всей левой трети кадра. Число трубок на пиксель растёт ровно как
            // 1/facing, поэтому и сила каждой обязана падать почти как facing;
            // остаток 0.18 оставлен только на то, чтобы силуэт венца не пропал
            // на боках вовсе.
            let crowd = 0.12 + 0.88 * lamp.facing
            let intensity = (0.16 + 0.84 * lamp.value) * (0.30 + 0.70 * depthFade)

            // Тон уходит в глубину вместе с яркостью. Раскалённая трубка
            // бледнеет к соломенному, и на дальней дуге это читалось так, будто
            // там горит жарче, чем впереди: самым белёсым местом кадра
            // оказывался самый дальний его край. В воздухе наоборот — даль
            // держит цвет и садится по яркости, а выбеливается только близкое.
            let heat = lamp.value * (0.42 + 0.58 * depthFade)
            let hue = hues.deep + (hues.hot - hues.deep) * heat
            let tint = Color(hue: hue,
                             saturation: palette.saturation * (0.92 - 0.45 * heat),
                             brightness: 1)

            // Стекло: почти невидимое, и на дальней дуге почти не видное вовсе.
            // Там трубки заходят одна за другую по пять штук на свою ширину,
            // и полупрозрачные тела складывались в сплошную чешую — дальний
            // край венца читался не стеклом, а листом позеленевшей жести,
            // из которого торчат нити. Гаснет стекло с глубиной вдвое круче
            // самой нити: нить — это свет, а тело трубки — только вещество,
            // и в дымке оно пропадает первым.
            let body = 0.30 + 0.70 * depthFade
            context.fill(lamp.glass, with: .color(tint.opacity((0.05 + 0.09 * intensity) * body)))
            context.stroke(lamp.glass,
                           with: .color(tint.opacity((0.12 + 0.22 * intensity) * body)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008), lineJoin: .round))

            // Нить — единственное яркое место. Три обводки: широкий ореол,
            // тело нити и раскалённая сердцевина. Ореол сжимается вместе
            // с трубкой: он и есть тот слой, который на боковых краях
            // расползался поверх соседей.
            context.blendMode = .plusLighter
            context.stroke(lamp.filament,
                           with: .color(tint.opacity((0.06 + 0.26 * intensity) * crowd)),
                           style: StrokeStyle(lineWidth: max(1.0, base * 0.0046 * crowd),
                                              lineCap: .round))
            context.stroke(lamp.filament,
                           with: .color(tint.opacity((0.20 + 0.48 * intensity) * (0.24 + 0.76 * lamp.facing))),
                           style: StrokeStyle(lineWidth: max(0.9, base * 0.0018), lineCap: .round))
            // Сердцевина остаётся золотой и на полном накале. Прежняя
            // насыщенность падала к 0.05 — то есть в чистый белый, — и
            // раскалённая часть венца теряла цвет ровно там, где он всего
            // нужнее: горячая нить в лампе не белая, а соломенная.
            context.stroke(lamp.filament,
                           with: .color(Color(hue: hue,
                                              saturation: palette.saturation * (0.44 - 0.26 * heat),
                                              brightness: 1).opacity((0.30 + 0.68 * intensity) * (0.30 + 0.70 * lamp.facing))),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008), lineCap: .round))

            // Макушка — раскалённый шарик на конце нити, а не колпачок поверх
            // трубки. Прежняя белая точка стояла на постоянной подложке в 0.06
            // и потому садилась на КАЖДУЮ трубку, включая почти погасшие: на
            // тёмном поле шесть сотых белого дают серое пятно ярче самой нити,
            // и весь венец получал по серой шляпке на столбик — не свет,
            // а гвозди, вбитые в трубки. На кадре это было первое, что видно
            // в дальней дуге: ряд серых колпачков над рядом оранжевых нитей.
            //
            // Подложка убрана целиком, сила взята квадратом накала — у тусклой
            // трубки макушки нет вовсе, — а цвет тот же соломенный, что у
            // сердцевины. Белым на этой сцене светится только самое горячее,
            // и добирается до белого макушка сама, через сложение.
            let tipHeat = intensity * intensity
            let tipSize = max(0.5, lamp.tipSize * (0.34 + 0.66 * lamp.facing)
                * (0.58 + 0.42 * tipHeat))
            context.fill(
                Path(ellipseIn: CGRect(x: lamp.tip.x - tipSize, y: lamp.tip.y - tipSize * 0.7,
                                       width: tipSize * 2, height: tipSize * 1.4)),
                with: .color(Color(hue: hue,
                                   saturation: palette.saturation * (0.32 - 0.24 * heat),
                                   brightness: 1)
                    .opacity((0.10 * intensity + 0.52 * tipHeat) * (0.30 + 0.70 * lamp.facing))))
            context.blendMode = .normal

            if let peak = lamp.peak {
                context.stroke(peak,
                               with: .color(.white.opacity(0.12 + 0.24 * depthFade)),
                               style: StrokeStyle(lineWidth: max(0.5, base * 0.0009), lineCap: .round))
            }
        }

        if !stageDrawn {
            stage.draw(&context, project: projectStatic, radius: radius,
                       maxHeight: maxHeight, base: base)
        }

        // Лучи рисуются последними и ложатся поверх фигур: свет от ламп должен
        // падать НА сцену, а не находиться где-то рядом с ней.
        GlassStage.beams(&context, from: beamSources,
                         centre: projectStatic(0, -maxHeight * 0.10, 0).0,
                         podiumRadius: radius,
                         hues: hues, saturation: palette.saturation,
                         energy: energy)

        drawLevelScale(&context, project: projectStatic, radius: radius,
                       maxHeight: maxHeight, base: base)
        // Шкала частот вращается вместе с венцом: она размечает именно его,
        // а не картинку. Нарисованная неподвижной проекцией, она оставалась
        // стоять, пока столбики уезжали мимо, — и подпись «43 Гц» показывала
        // на ту полосу, которая давно ушла в другое место круга.
        drawBaseRing(&context, project: project, radius: radius,
                     base: base, centre: centre, hues: hues)
    }

    /// Шкала уровня по высоте: тонкие кольца на характерных отметках в децибелах
    /// и подписи к ним. Раньше высота колонок была величиной без единиц измерения —
    /// теперь по ней можно читать уровень, а не только сравнивать столбики между собой.
    private func drawLevelScale(_ context: inout GraphicsContext,
                                project: (Double, Double, Double) -> (CGPoint, Double, Double),
                                radius: Double,
                                maxHeight: Double,
                                base: Double)
    {
        // Отметки выбраны по децибелам, а не по долям: -12 дБ это ровно четверть
        // амплитуды, и глазу привычнее видеть шкалу прибора.
        let marks: [(level: Double, text: String)] = [
            (0.251, "−12"), (0.501, "−6"), (0.708, "−3"), (1.0, "0 dB"),
        ]
        let rim = radius * Self.scaleRim

        // Кольца шкалы обходят настил стороной. Кольцо радиусом чуть больше
        // венца всё равно перекрывает сцену: наклон камеры кладёт его дальнюю
        // и ближнюю дуги мимо помоста, а боковые — прямо по стеклу, и на
        // полированной плите оказывалась белая штриховая линия. Разметка
        // прибора висит в воздухе вокруг венца, а не лежит на сцене.
        var rings = context
        rings.clip(to: GlassStage.deckOutline(project, radius: radius, ring: 1,
                                              level: maxHeight * GlassStage.deckLift),
                   options: .inverse)

        for mark in marks {
            let height = maxHeight * mark.level
            var ring = Path()
            for step in 0...120 {
                let theta = Double(step) / 120 * 2 * .pi
                let point = project(cos(theta) * rim, -height,
                                    sin(theta) * rim).0
                if step == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
            }
            // Ноль децибел — не такая же отметка, как прочие, а потолок шкалы,
            // и рисуется он сплошным. Дальняя дуга этого кольца проходит выше
            // самых высоких столбиков и оказывается верхней линией всего кадра:
            // пунктиром в одну десятую по чёрному она читалась царапиной, а
            // сплошной становится тем, чем является, — краем, до которого венцу
            // позволено дорасти. Заодно у верха кадра появляется своя черта
            // против обода шкалы частот внизу.
            let ceiling = mark.level == 1.0
            // Ближняя дуга кольца гаснет. Кольцо — обруч в пространстве, и
            // ближняя его половина проходит ПЕРЕД венцом: сплошная, она ложилась
            // серой проволокой поперёк раскалённых трубок. Гашение считается
            // одним вертикальным градиентом по габариту кольца — на этой камере
            // верх габарита это в точности дальняя дуга, а низ ближняя, и
            // сто двадцать отдельных обводок с разной прозрачностью ради того
            // же результата кадр бы не окупил. До половины высоты сила полная:
            // там боковые края кольца, на которых стоят отметки мачт.
            let bounds = ring.boundingRect
            rings.stroke(ring,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: .white.opacity(ceiling ? 0.13 : 0.055),
                                       location: 0),
                                 .init(color: .white.opacity(ceiling ? 0.13 : 0.055),
                                       location: 0.52),
                                 .init(color: .white.opacity(0), location: 0.88),
                             ]),
                             startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                             endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)),
                         style: StrokeStyle(lineWidth: max(0.4, base * 0.0006),
                                            dash: ceiling ? []
                                                : [base * 0.004, base * 0.010]))
        }

        // Две мачты по бокам — то, чего шкале не хватало, чтобы стать прибором,
        // а не подписью рядом с картинкой. Стоят они не «слева от кадра», а ровно
        // на наружном ободе шкалы частот: тот же радиус, что и кончики её засечек.
        // От этого две разметки становятся одной оснасткой — круг по полу меряет
        // спектр, мачты на его ободе меряют уровень, и кольца уровня проходят
        // через отметки мачт. Раньше столбец подписей висел в чёрном поле в сотне
        // пикселей от колец, которые подписывал, и ни к чему на кадре не крепился.
        //
        // Мачт две, а не одна: венец зеркальный, и у зеркальной формы прибор
        // тоже обязан быть парным. Одиночный столбец слева оставлял правую
        // половину поля пустой — предмет без пары в симметричном кадре.
        // Цифры при этом только на левой: две одинаковых колонки чисел
        // читались бы не парой, а дублем.
        for side in [-1.0, 1.0] {
            let foot = project(rim * side, 0, 0).0
            let head = project(rim * side, -maxHeight, 0).0
            var mast = Path()
            mast.move(to: foot)
            mast.addLine(to: head)
            // Мачта светлеет кверху: у пола она уходит в тень площадки, к нулю
            // децибел выходит на свет. Ровная по яркости, она читалась чертой,
            // прочерченной поверх кадра.
            context.stroke(mast,
                           with: .linearGradient(
                               Gradient(stops: [
                                   .init(color: .white.opacity(0.03), location: 0),
                                   .init(color: .white.opacity(0.16), location: 1),
                               ]),
                               startPoint: foot, endPoint: head),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))

            // Пятка: короткая засечка наружу по полу. Мачта на неё опирается,
            // и видно, что она стоит на ободе, а не подвешена в воздухе.
            let heel = project(rim * side * 1.045, 0, 0).0
            var base0 = Path()
            base0.move(to: foot)
            base0.addLine(to: heel)
            context.stroke(base0, with: .color(.white.opacity(0.16)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))
        }

        for mark in marks {
            let height = maxHeight * mark.level
            for side in [-1.0, 1.0] {
                let node = project(rim * side, -height, 0).0
                let arm = base * (mark.level == 1.0 ? 0.0092 : 0.0068)
                var tick = Path()
                tick.move(to: CGPoint(x: node.x - arm, y: node.y))
                tick.addLine(to: CGPoint(x: node.x + arm, y: node.y))
                context.stroke(tick,
                               with: .color(.white.opacity(mark.level == 1.0 ? 0.34 : 0.22)),
                               style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))
            }

            // Подпись висит на левой мачте, за её отметкой. Столбец от этого
            // не вертикальный, а с тем же завалом, что и мачта: перспектива
            // разводит верх и низ вертикали, и поставленные по отвесу цифры
            // разъезжались бы с отметками, которые подписывают.
            let node = project(-rim, -height, 0).0
            var text = context.resolve(
                Text(mark.text)
                    .font(.system(size: base * 0.0145, weight: .medium, design: .rounded)))
            text.shading = .color(.white.opacity(mark.level == 1.0 ? 0.38 : 0.30))
            context.draw(text,
                         at: CGPoint(x: node.x - base * 0.016, y: node.y),
                         anchor: .trailing)
        }
    }

    /// Радиус всей приборной оснастки в долях радиуса венца: обод шкалы частот,
    /// пятки мачт и кольца шкалы уровня стоят на нём одном. Величина общая
    /// нарочно — на ней держится связь двух шкал, и разъехаться они не должны.
    private static let scaleRim = 1.105

    /// Кольцо-основание с засечками на настоящих границах полос WLED и подписями
    /// частот. Мелкая деталь, но осмысленная: видно, где какая полоса стоит.
    private func drawBaseRing(_ context: inout GraphicsContext,
                              project: (Double, Double, Double) -> (CGPoint, Double, Double),
                              radius: Double,
                              base: Double,
                              centre: CGPoint,
                              hues: (deep: Double, hot: Double))
    {
        // Дальняя половина всей оснастки гаснет. Кольцо лежит на полу ЗА венцом:
        // между ним и камерой сто двадцать восемь горящих трубок, ферма и вся
        // группа, и видно его там быть не может в принципе. А рисовалось оно
        // ровным по кругу и последним слоем — на кадре дальняя дуга ложилась
        // поверх фермы, и белые засечки читались серыми царапинами на её поясах,
        // единственным холодным пятном в верхней трети картинки.
        //
        // Гашение вертикальным градиентом по габариту, а не обрезкой: у круга,
        // лежащего на полу, экранная высота — строго монотонная функция глубины,
        // поэтому один градиент сверху вниз это в точности гашение по глубине.
        // Полная сила начинается с 0.42 габарита — там боковые точки кольца,
        // которые от зрителя не заслонены ничем.
        /// Раскладка «даль тусклее ближней дуги» по габариту кольца.
        func depthFade(_ bounds: CGRect, _ alpha: Double) -> GraphicsContext.Shading {
            .linearGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.6,
                                       brightness: 1).opacity(alpha * 0.10), location: 0),
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.6,
                                       brightness: 1).opacity(alpha), location: 0.42),
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.6,
                                       brightness: 1).opacity(alpha), location: 1),
                ]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY))
        }

        var ring = Path()
        for step in 0...144 {
            let theta = Double(step) / 144 * 2 * .pi
            let point = project(cos(theta) * radius * 1.055, 0, sin(theta) * radius * 1.055).0
            if step == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
        }
        context.stroke(ring, with: depthFade(ring.boundingRect, 0.14),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))

        // Наружный обод по кончикам засечек. На нём стоят мачты шкалы уровня,
        // и через него замыкается вся оснастка: без обода засечки кончались
        // в воздухе тридцатью отдельными чёрточками, а мачты не на что было
        // поставить. Обод бледнее внутреннего кольца — он край разметки,
        // а не сама разметка.
        var brim = Path()
        for step in 0...144 {
            let theta = Double(step) / 144 * 2 * .pi
            let point = project(cos(theta) * radius * Self.scaleRim, 0,
                                sin(theta) * radius * Self.scaleRim).0
            if step == 0 { brim.move(to: point) } else { brim.addLine(to: point) }
        }
        context.stroke(brim, with: depthFade(brim.boundingRect, 0.075),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0007)))

        // Засечки стоят ровно на тех же долях круга, что и подписи: полоса band
        // приходится на position = band/15 * 0.5 и на её зеркало. Прежний обход
        // по band/31 давал тридцать две равномерные чёрточки, ни одна из которых
        // не совпадала с границей полосы, — поводок от подписи приходил мимо
        // своей засечки на пару градусов, и разметка попросту врала.
        //
        // Полосы 0 и 15 — швы зеркала: на них две половины спектра сходятся,
        // и там засечка одна на обе. Шов и отмечен длиннее прочих: без него
        // одинаковые числа по обе стороны читались сбоем отрисовки, а не
        // разворотом шкалы. Со швом видно, что круг — это спектр туда и обратно.
        for band in 0...15 {
            let seam = band == 0 || band == 15
            let half = Double(band) / 15 * 0.5
            for position in seam ? [half] : [half, 1 - half] {
                let theta = position * 2 * .pi
                let inner = project(cos(theta) * radius * 1.055, 0,
                                    sin(theta) * radius * 1.055).0
                let outerPoint = project(cos(theta) * radius * Self.scaleRim, 0,
                                         sin(theta) * radius * Self.scaleRim)
                let outer = outerPoint.0
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                // Та же мера, что у колец, только считанная прямо по глубине:
                // засечка — короткий отрезок, и градиент по её собственному
                // габариту дал бы бессмыслицу. Дальняя дуга уходит в десятую
                // силы: там засечки лежали белыми чёрточками поверх фермы.
                let away = max(0, min(1, outerPoint.2 / (radius * 0.40)))
                let show = 1 - 0.90 * away
                context.stroke(tick,
                               with: .color(.white.opacity(show * (seam ? 0.26
                                                : (band % 2 == 0 ? 0.16 : 0.070)))),
                               style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))

                // Шов помечен не длинной засечкой, а треугольным индексом на
                // ободе. Длинная засечка на кадре не отличалась от поводка
                // подписи — та же серая черта той же длины, торчащая из обода, —
                // и разметка получала два разных знака одного начертания.
                // Треугольник ни с чем не спутать: у приборов так и ставят
                // индекс, и он один объясняет, почему числа по кругу идут
                // туда и обратно.
                // Индекс живёт только на ближней дуге, по тому же правилу, что
                // и подписи. На дальней он ложится прямо в частокол горящих
                // трубок и читается серой галочкой, севшей на венец, — знаком
                // непонятно от чего. Шов на дальней стороне и подписывать нечем:
                // цифры туда тоже не выходят.
                guard seam else { continue }
                let shown = max(0, min(1, (outer.y - centre.y) / (radius * 0.34)))
                guard shown > 0.35 else { continue }
                // Индекс приземист, а не вытянут. Прежний был втрое длиннее
                // своей ширины и сидел на конце засечки — а засечка приходит
                // к нему прямой чертой: вместе они складывались в линию
                // со стрелкой на конце, то есть в курсор мыши, случайно
                // оставленный поверх кадра. Пробовал развернуть остриём
                // к шкале — вышло только хуже: получилась та же стрелка,
                // только целящаяся внутрь. Дело было не в направлении,
                // а в пропорции: у приборного индекса треугольник шире,
                // чем длиннее, и потому сидит на ободе меткой, а не летит
                // по нему указателем.
                let tipPoint = project(cos(theta) * radius * (Self.scaleRim + 0.020), 0,
                                       sin(theta) * radius * (Self.scaleRim + 0.020)).0
                let run = CGPoint(x: tipPoint.x - outer.x, y: tipPoint.y - outer.y)
                let span = max(0.001, hypot(run.x, run.y))
                let sideways = CGPoint(x: -run.y / span * base * 0.0064,
                                       y: run.x / span * base * 0.0064)
                var index = Path()
                index.move(to: tipPoint)
                index.addLine(to: CGPoint(x: outer.x + sideways.x, y: outer.y + sideways.y))
                index.addLine(to: CGPoint(x: outer.x - sideways.x, y: outer.y - sideways.y))
                index.closeSubpath()
                context.fill(index, with: .color(.white.opacity(0.30 * shown)))
            }
        }

        // Подписи на характерных частотах — по таблице полос прошивки.
        // Подписи по границам полос из таблицы прошивки — через одну, чтобы
        // разметка была частой, но ещё читалась.
        let edges = [43, 86, 129, 216, 301, 430, 560, 818, 1120,
                     1421, 1895, 2412, 3015, 3704, 4479, 9259]
        let labels: [(band: Int, text: String)] = stride(from: 0, through: 15, by: 2).map { band in
            let hz = edges[band]
            let text = hz >= 1000
                ? String(format: "%.1fk", Double(hz) / 1000)
                : "\(hz)"
            return (band, text)
        }
        // Полоса встречается на круге дважды: венец зеркальный, и правая
        // половина повторяет левую. Подписываются обе — раньше из пары брался
        // только ближний к зрителю, и разметка обрывалась на середине круга,
        // будто спектр кончается на четырёх с половиной килогерцах.
        var placed: [(text: String, position: Double)] = []
        for label in labels {
            let first = Double(label.band) / 15 * 0.5
            placed.append((label.text, first))
            placed.append((label.text, 1 - first))
        }
        // Пара близких к шву подписей сходится на экране почти в одну точку:
        // у зеркала обе половины там встречаются. Два одинаковых числа в
        // полутора сантиметрах друг от друга читаются не симметрией, а сбоем,
        // и на кадре внизу справа стояли два «4.5k» подряд. Из такой пары
        // остаётся одна — вдали от шва обе половины расходятся широко, и там
        // повтор снова становится симметрией.
        var taken: [(text: String, at: CGPoint)] = []
        for label in placed {
            let chosenAngle = label.position * 2 * .pi
            let projected = project(cos(chosenAngle) * radius * 1.20, 0,
                                    sin(chosenAngle) * radius * 1.20)
            let chosen = (projected.0, projected.2)

            // Подписи живут только на передней дуге: на дальней они лезут
            // на колонны и читаются мусором поверх света. Раньше тут стоял
            // жёсткий порог, и при неподвижной шкале этого хватало — теперь
            // она едет, и на пороге подпись просто мигала бы. Гаснет она
            // постепенно, на длине в четверть радиуса.
            // Порог поднят до самой середины круга. Прежний пускал подписи
            // на боковые края, а там теперь стоят мачты шкалы уровня: цифра
            // садилась ровно на пятку мачты, и поводок шёл поперёк неё —
            // на кадре справа получался узел из четырёх линий и числа.
            // Заодно разметка собралась на ближней дуге, где её и читают.
            let edge = centre.y
            let fade = max(0, min(1, (chosen.0.y - edge) / (radius * 0.34)))
            guard fade > 0.02 else { continue }
            // Мерка — четверть круга. Дальше этого одинаковые числа стоят
            // по разные стороны венца и читаются симметрией; ближе — сходятся
            // к шву и читаются двоением.
            let twinned = taken.contains {
                $0.text == label.text && hypot($0.at.x - chosen.0.x,
                                               $0.at.y - chosen.0.y) < radius * 0.75
            }
            guard !twinned else { continue }
            taken.append((label.text, chosen.0))

            // Поводок от обода к подписи: без него цифра висит в пустоте
            // рядом с венцом, а не подписывает его засечку.
            let leaderStart = project(cos(chosenAngle) * radius * Self.scaleRim, 0,
                                      sin(chosenAngle) * radius * Self.scaleRim).0
            var leader = Path()
            leader.move(to: leaderStart)
            leader.addLine(to: CGPoint(
                x: leaderStart.x + (chosen.0.x - leaderStart.x) * 0.55,
                y: leaderStart.y + (chosen.0.y - leaderStart.y) * 0.55))
            context.stroke(leader, with: .color(.white.opacity(0.16 * fade)),
                           style: StrokeStyle(lineWidth: max(0.4, base * 0.0006)))

            var text = context.resolve(
                Text(label.text)
                    .font(.system(size: base * 0.0145, weight: .medium, design: .rounded)))
            text.shading = .color(.white.opacity(0.30 * fade))
            context.draw(text, at: chosen.0, anchor: .center)
        }
    }
}
