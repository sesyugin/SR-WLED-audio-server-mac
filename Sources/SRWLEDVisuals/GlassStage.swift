import SwiftUI

/// Сцена в центре венца: подиум, колонки и группа музыкантов изо льда.
///
/// Фигуры собраны из объёмных тел — сфер, капсул и коробок, заданных в трёхмерных
/// координатах. Прежняя версия рисовала плоские силуэты, и никакая отделка не могла
/// сделать их объёмными: у плоского контура нет нормали, а значит нечему ловить свет.
/// Здесь у каждого тела своя светотень, а все тела сортируются по глубине общим
/// списком, поэтому рука заходит за корпус, а корпус за колонку.
///
/// Лёд намеренно холодный независимо от гаммы сцены: тёплые лампы вокруг и холодные
/// фигуры в центре дают контраст, на котором держится картинка.
struct GlassStage {
    let palette: Palette
    /// Общая громкость: от неё зависит накал льда.
    let energy: Double
    /// Бас: от него дышат колонки и бочка.
    let bass: Double
    /// Верхние частоты: от них вспыхивают блики.
    let air: Double
    let beat: Double
    /// Время сцены в секундах: по нему качаются фигуры.
    let time: Double

    /// Стекло фигуры. `density` — плотность заливки: у всех она одна, и поднята
    /// только у вокалиста. Он единственный, кого судят по силуэту на голом полу:
    /// у остальных за спиной либо своя установка, либо портал, и они читаются
    /// перепадом с ними, а певец стоит один на самом тёмном месте подиума, где
    /// сквозное тело просто растворяется.
    private func ice(glow: Double, density: Double = 0.52) -> Solid3D.Material {
        Solid3D.Material(saturation: 0.88, glow: min(1, glow), opacity: density)
    }

    // MARK: - Движение
    //
    // Позы связаны с музыкой двумя разными вещами. Медленная волна даёт
    // покачивание корпусом — то, что музыкант делает непрерывно, пока играет.
    // Удар даёт короткий толчок: кивок, приседание, замах. Смешивать их нельзя:
    // качка от удара выходит дёрганой, а замах от волны — вялым.

    /// Насколько сцена жива. Все амплитуды домножены на эту величину, поэтому
    /// в тишине фигуры замирают: движение приходит из музыки, а не идёт само
    /// по себе, как заводная игрушка.
    private var live: Double { min(1, energy * 1.3) }

    /// Волна общего темпа сцены. 2.4 рад/с — период около двух с половиной
    /// секунд: это покачивание корпусом, а не тряска. У каждого музыканта свой
    /// сдвиг фазы и свой множитель темпа: качаться в ногу они не должны —
    /// синхронная группа читается строем, а не живыми людьми.
    private func wave(_ phase: Double, rate: Double = 1) -> Double {
        sin(time * 2.4 * rate + phase)
    }

    func draw(_ context: inout GraphicsContext,
              project: @escaping Solid3D.Projection,
              radius: Double,
              maxHeight: Double,
              base: Double)
    {
        let line = max(0.4, base * 0.0009)

        // Высота помоста. Сцена — не круг, нарисованный на полу, а настил
        // с толщиной: у настоящей площадки есть кромка, и по ней глаз и
        // понимает, что люди стоят на возвышении, а не на общем полу зала.
        //
        // Поднимается всё разом обёрткой над проекцией: на сцене за три сотни
        // тел, и поднимать их поштучно — это триста мест, где можно забыть.
        // Помост рисуется исходной проекцией, от пола до своей крышки,
        // а всё остальное — этой: для неё ноль высоты приходится на настил.
        let deck = maxHeight * 0.135
        let onDeck: Solid3D.Projection = { x, y, z in project(x, y - deck, z) }

        drawPodium(&context, project: project, radius: radius, base: base, deck: deck)

        // Рост фигур задан в долях высоты венца, положение — в долях его радиуса.
        // Знак z: положительный уходит от зрителя.
        // Общий множитель поднят: венец шириной в два радиуса, а вся группа
        // занимала едва треть подиума, и люди в ней читались фигурками в
        // масштабной модели зала. Дальше поднимать нельзя — дальний угол
        // развёрнутого стека портала подходит к самому краю подиума.
        let stand = maxHeight * 1.14
        var pieces: [Solid3D.Piece] = []

        // Положения заданы в долях радиуса венца и переводятся в мировые единицы.
        // Без перевода вся группа схлопывается в точку посреди сцены.
        func place(_ x: Double, _ z: Double) -> (Double, Double) {
            (x * radius, z * radius)
        }

        // Вся группа сдвинута к зрителю на 0.05 радиуса. Подиум — круг, а
        // раскладка стояла в его дальней половине: перед вокалистом оставалась
        // пустая треть сцены, и центр тяжести кадра уезжал вверх, к ферме.
        pieces += drummer(at: place(0.00, 0.37), height: stand * 0.40,
                          project: onDeck, line: line)
        // Портал стоит на подиуме, а не за ним: дальний угол развёрнутого стека
        // ложится на 0.69 радиуса при крае подиума 0.72 — у самой кромки, но
        // целиком на сцене.
        // Стек убавлен и отодвинут наружу ради коридора между ним и клавишами:
        // прежний кабинет подходил к инструменту вплотную, и микрофонная стойка,
        // которой полагается стоять между ними, садилась прямо на его фасад —
        // проход был уже самой стойки. Заодно ушла и лишняя весомость портала:
        // два глухих ящика были самыми крупными и яркими телами сцены и тянули
        // взгляд в углы, мимо музыкантов.
        pieces += speaker(at: place(-0.545, 0.17), height: stand * 0.385, turn: -0.34,
                          project: onDeck, line: line)
        pieces += speaker(at: place( 0.545, 0.17), height: stand * 0.385, turn: 0.34,
                          project: onDeck, line: line)
        pieces += guitarist(at: place(-0.30, -0.09), height: stand * 0.44,
                            project: onDeck, line: line)
        pieces += keyboardist(at: place(0.30, -0.07), height: stand * 0.42,
                              project: onDeck, line: line)
        // Рост вокалиста считан по экрану, а не назначен на глаз. Камера с
        // перспективой: вынесенный к зрителю на 0.37 радиуса певец и так
        // получает прибавку в масштабе, и прежние 0.50 роста давали на кадре
        // фигуру на семнадцать процентов выше гитариста — среди своих он
        // выглядел не фронтменом, а взрослым в компании подростков.
        // Мерка — силуэт целиком, от макушки до нижней стопы: 0.437 давали
        // 105 пикселей против 95 у гитариста, то есть всё ещё десятую часть
        // сверху. Здесь 99 против 95 — фронтмен впереди группы и должен быть
        // чуть крупнее, но именно чуть.
        pieces += vocalist(at: place(0.00, -0.37), height: stand * 0.414,
                           project: onDeck, line: line)

        // Ферма позади группы: единственное, что стоит выше людей, — поэтому
        // она и читается сценой, а не помостом с фигурами.
        pieces += lightRig(radius: radius, stand: stand, project: onDeck, line: line)

        // Стойки стоят вполоборота сбоку от гитариста и клавишника: журавль
        // заведён обратно к музыканту, к его лицу.
        // Журавль поднят выше макушки не по недосмотру: он вынесен к зрителю,
        // а всё вынесенное съезжает по экрану вниз — на кадре микрофон
        // приходит музыканту как раз к лицу.
        // Обе стойки стоят ровно в коридоре между музыкантом и порталом, и
        // вынос по глубине у них задан не на глаз: на этой камере глубина
        // ложится на экран круче высоты, и микрофон приходит музыканту к лицу
        // только при своём выносе к зрителю. Отодвинь стойку назад — головка
        // уедет выше макушки, подай вперёд — упадёт к поясу.
        pieces += micStand(base: place(-0.400, -0.190), height: stand * 0.46,
                           boom: (stand * 0.082, -stand * 0.112, radius * 0.045),
                           phase: 1.1, project: onDeck, line: line)
        pieces += micStand(base: place(0.402, -0.168), height: stand * 0.44,
                           boom: (-stand * 0.070, -stand * 0.098, radius * 0.045),
                           phase: 2.9, project: onDeck, line: line)

        // Мониторы у края подиума, вдоль передней дуги. Вся передняя мелочь
        // подтянута внутрь почти на десятую радиуса: помост поднялся, и то,
        // что стояло у самой кромки, оказалось на экране вровень с ближними
        // столбиками венца. На громком басе они вырастают во весь рост и
        // закрывали передний ряд целиком — клин, кофр и бухту разом.
        // Дальше выносить нельзя:
        // край подиума на 0.72 радиуса, а вправо и влево от середины передняя
        // дуга уходит под самый венец, и клин ложится на светящиеся столбики.
        // Клинья разнесены по дуге, по одному на музыканта: сдвинутые к середине,
        // все три встают в кучу под вокалистом, а перед гитаристом и клавишником
        // остаётся пустой пол.
        // Три клина стояли ровной дугой, одного калибра и с одним завалом
        // панели, и читались одним бруском, размноженным по кругу. Разведены
        // они теперь по всем трём приметам разом: калибр, доворот и завал.
        // Одинаковыми они и не бывают — на площадке это разные ящики из разных
        // комплектов, и ставит их ногой тот, кому за ними петь.
        pieces += monitor(at: place(-0.392, -0.425), width: stand * 0.104, turn: -0.86,
                          rake: 0.54, project: onDeck, line: line)
        // Средний клин довёрнут чуть вбок: поставленный анфас, он показывает
        // камере одну грань и читается плоской карточкой — тем же, чем читались
        // неразвёрнутые колонки портала.
        pieces += monitor(at: place(0.000, -0.462), width: stand * 0.132, turn: 0.22,
                          rake: 0.41, project: onDeck, line: line)
        pieces += monitor(at: place(0.398, -0.395), width: stand * 0.116, turn: 0.46,
                          rake: 0.50, project: onDeck, line: line)

        // Мелочь передней кромки. Пустая треть кадра — не про нехватку
        // предметов, а про то, что край сцены выглядел выметенным: на живой
        // площадке у кромки всегда лежит то, что не влезло в фуру.
        // Кофр и бухта разнесены по разным половинам и стоят чуть впереди
        // клиньев: встав с ними в один ряд, они удлинили бы ту же дугу,
        // от которой передний план и рассыпался.
        pieces += roadCase(at: place(-0.208, -0.480), width: stand * 0.102, turn: 0.42,
                           project: onDeck, line: line)
        pieces += cableCoil(at: place(0.210, -0.500), radius: stand * 0.058,
                            gauge: stand * 0.0088,
                            tail: place(0.330, -0.372),
                            project: onDeck, line: line)

        // Кабели от инструментов к порталу. Провода объясняют, откуда у сцены
        // звук: без них и гитара, и клавиши стоят сами по себе, а колонки —
        // сами по себе.
        // Шнур тоньше прежнего почти вдвое. У этого материала светится кромка
        // на просвет, а у тонкой капсулы кромка занимает всю её ширину: чем
        // толще был провод, тем ярче он горел — и от гитары к порталу тянулся
        // не кабель, а канат в подсветке, самый заметный предмет в углу сцены.
        let gauge = stand * 0.0026
        pieces += cable(from: (place(-0.350, -0.145).0, -stand * 0.245, place(-0.350, -0.145).1),
                        to: (place(-0.487, 0.095).0, 0, place(-0.487, 0.095).1),
                        bow: radius * 0.028, hang: stand * 0.085, gauge: gauge,
                        project: onDeck, line: line)
        pieces += cable(from: (place(0.362, -0.125).0, -stand * 0.185, place(0.362, -0.125).1),
                        to: (place(0.500, 0.095).0, 0, place(0.500, 0.095).1),
                        bow: -radius * 0.026, hang: stand * 0.070, gauge: gauge,
                        project: onDeck, line: line)
        // Шнура от микрофона к монитору здесь больше нет. Он шёл через
        // всю фигуру вокалиста и через передний клин — две самые заметные
        // вещи в нижней трети кадра, — и объяснял ровно ничего: у певца
        // на такой сцене радиосистема, а не провод под ногами.

        // Общая сортировка: без неё тела накладываются в порядке создания
        // и объём рассыпается. В списке около 320 тел — это и есть цена кадра,
        // потому что сортировка и отрисовка идут по нему целиком. Каждая новая
        // мелочь считается здесь поштучно: бухта кабеля стоит одиннадцать тел,
        // столько же, сколько весь стек портала с динамиками.
        pieces.sort { $0.depth > $1.depth }
        for piece in pieces {
            piece.render(&context)
        }
    }

    // MARK: - Подиум

    /// Помост: шестнадцатигранный настил с толщиной, а не круг, залитый на полу.
    ///
    /// Граней ровно шестнадцать, и это не круглое число наугад: столько же полос
    /// в спектре у прошивки WLED, столько же засечек на кольце частот вокруг.
    /// Помост оказывается той же разметкой, только в плане — сцена и шкала
    /// говорят об одном и том же.
    ///
    /// Гранёный борт — приём ретро: у станка, собранного из щитов, кромка
    /// ломаная, и каждый щит ловит свет по-своему. Гладкий цилиндр читается
    /// точёной деталью, гранёный — построенным.
    private func drawPodium(_ context: inout GraphicsContext,
                            project: Solid3D.Projection,
                            radius: Double,
                            base: Double,
                            deck: Double)
    {
        let podiumRadius = radius * 0.72
        let facets = 16
        // Полграни поворота: без него вершина многоугольника приходится точно
        // на середину переднего края, и помост показывает зрителю ребро вместо
        // щита. Фасадом вперёд он читается сценой, ребром — кристаллом.
        let phase = .pi / Double(facets)

        /// Вершина многоугольника: номер и высота от пола.
        func corner(_ index: Int, _ level: Double) -> (CGPoint, Double) {
            let theta = Double(index) / Double(facets) * 2 * .pi + phase
            let projected = project(cos(theta) * podiumRadius, -level, sin(theta) * podiumRadius)
            return (projected.0, projected.2)
        }

        /// Замкнутый контур настила на заданной высоте.
        func outline(_ level: Double) -> Path {
            var path = Path()
            for index in 0...facets {
                let point = corner(index % facets, level).0
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }

        // Подложка борта: весь пояс разом, в самом тёмном тоне. Грани лягут
        // поверх неё, и на их общих краях не останется волосяных просветов —
        // у соседних заливок край один, а сглаживание считает его дважды.
        var apron = Path()
        for index in 0...facets {
            let point = corner(index % facets, deck).0
            if index == 0 { apron.move(to: point) } else { apron.addLine(to: point) }
        }
        for index in stride(from: facets, through: 0, by: -1) {
            apron.addLine(to: corner(index % facets, 0).0)
        }
        apron.closeSubpath()
        context.fill(apron, with: .color(Color(hue: 0.030, saturation: 0.95, brightness: 0.055)))

        // Щиты борта, от дальних к ближним. Дальние всё равно уйдут под крышку,
        // но отбраковывать их отдельно незачем: порядок по глубине закрывает
        // их сам, а шестнадцать путей на кадр дешевле одной фигуры.
        var panels: [(path: Path, depth: Double, lit: Double)] = []
        for index in 0..<facets {
            let mid = (Double(index) + 0.5) / Double(facets) * 2 * .pi + phase
            let topFrom = corner(index, deck), topTo = corner((index + 1) % facets, deck)
            let footFrom = corner(index, 0), footTo = corner((index + 1) % facets, 0)

            var path = Path()
            path.move(to: topFrom.0)
            path.addLine(to: topTo.0)
            path.addLine(to: footTo.0)
            path.addLine(to: footFrom.0)
            path.closeSubpath()

            // Освещённость щита по его развороту: свет падает сверху-слева,
            // значит ярче всего левый передний скат, темнее всего правый задний.
            let facing = max(0, cos(mid + .pi / 2 + 0.55))
            panels.append((path, (topFrom.1 + footTo.1) / 2, 0.10 + 0.66 * facing))
        }
        panels.sort { $0.depth > $1.depth }

        for panel in panels {
            let bounds = panel.path.boundingRect
            context.fill(panel.path,
                         with: .linearGradient(
                             Gradient(colors: [
                                 Color(hue: 0.042 + 0.034 * panel.lit,
                                       saturation: 0.94 - 0.28 * panel.lit,
                                       brightness: 0.085 + 0.44 * panel.lit),
                                 Color(hue: 0.030, saturation: 0.96,
                                       brightness: 0.028 + 0.085 * panel.lit),
                             ]),
                             startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                             endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
        }

        // Рёбра между щитами: тонкая светлая линия по каждому стыку. У гранёного
        // тела ребро всегда ловит блик — по нему грань и отделяется от соседней,
        // когда обе повёрнуты к свету почти одинаково.
        var edges = Path()
        for index in 0..<facets {
            edges.move(to: corner(index, deck).0)
            edges.addLine(to: corner(index, 0).0)
        }
        context.blendMode = .plusLighter
        context.stroke(edges,
                       with: .color(Color(hue: 0.068, saturation: 0.50, brightness: 1)
                           .opacity(0.055 + 0.075 * energy)),
                       style: StrokeStyle(lineWidth: max(0.4, base * 0.0007)))
        context.blendMode = .normal

        // Крышка настила поверх борта: она и закрывает дальнюю половину.
        let disc = outline(deck)
        let bounds = disc.boundingRect
        context.fill(disc,
                     with: .linearGradient(
                         Gradient(colors: [
                             Color(hue: 0.075, saturation: 0.62, brightness: 1)
                                 .opacity(0.030 + 0.030 * energy),
                             Color(hue: 0.035, saturation: 0.9, brightness: 1).opacity(0.006),
                         ]),
                         startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                         endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))

        // Светящаяся кромка настила — то, по чему читается верхний край.
        // На площадке её и правда пускают лентой по борту сцены, так что
        // это не украшение, а та же деталь, что и всё остальное на помосте.
        context.blendMode = .plusLighter
        context.stroke(disc,
                       with: .color(Color(hue: 0.070, saturation: 0.55, brightness: 1)
                           .opacity(0.24 + 0.34 * energy)),
                       style: StrokeStyle(lineWidth: max(0.7, base * 0.0016)))

        // Отблеск на полу вокруг помоста: без него настил стоит на пустоте.
        context.stroke(outline(0),
                       with: .color(Color(hue: 0.045, saturation: 0.85, brightness: 1)
                           .opacity(0.07 + 0.10 * energy)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0011)))
        context.blendMode = .normal
    }

    // MARK: - Общая анатомия
    //
    // Все фигуры собраны по одной схеме и отличаются позой и реквизитом.
    // Разметка канонная: рост в семь с половиной голов, плечи в 0.22 роста,
    // локоть на середине руки, колено на середине ноги.

    /// Поза: то, чем фигуры отличаются друг от друга, если убрать реквизит.
    ///
    /// Все величины — в долях роста и все отсчитываются от таза: ниже него поза
    /// корпуса ничего не меняет, иначе наклон утаскивал бы за собой ступни.
    private struct Pose {
        /// Вынос плечевого пояса вперёд, к зрителю. Отрицательный отклоняет
        /// корпус назад — так стоит вокалист, вскинувший руку.
        var lean: Double = 0
        /// Разворот плеч вокруг вертикали, тангенс угла: при положительном
        /// правая половина корпуса выходит к зрителю, левая уходит назад.
        /// Разворот забирает с собой и то, что фигура держит в руках.
        var twist: Double = 0
        /// Боковой наклон корпуса: сдвиг плечевого пояса вбок относительно таза.
        var roll: Double = 0
        /// Ширина расстановки ног — множитель к базовой.
        var stance: Double = 1
        /// Перекос расстановки: прибавка к ширине одной ноги и такая же убавка
        /// у другой. Симметрично расставленные ноги на этой камере читаются
        /// присядкой — обе согнуты одинаково, и человек садится на невидимый
        /// стул. Стойка узнаётся перекосом: одна нога прямая под тазом, вторая
        /// отставлена в упор. Положительный перекос упирает правую ногу.
        var brace: Double = 0
        /// Шаг: правая нога вынесена к зрителю, левая отставлена назад.
        var stride: Double = 0
        /// Уровень тазобедренного сустава: у стоящего это половина роста,
        /// у сидящего — высота табурета. От него отсчитывается весь корпус,
        /// поэтому посадить фигуру можно, не трогая её пропорций.
        var hip: Double = 0.500
        /// Вынос макушки по глубине: отрицательный наклоняет голову к зрителю
        /// (взгляд вниз, на руки), положительный запрокидывает подбородок.
        var headTilt: Double = 0
    }

    /// Разметка фигуры в долях роста.
    ///
    /// Камера смотрит на сцену сверху, и наклон съедает вертикаль, но не ширину.
    /// Если задавать анатомию прямо в мировых единицах, в кадре выходит коротышка:
    /// рост сжимается почти вдвое, а голова и плечи остаются во всю ширину —
    /// отсюда и брались большеголовые человечки. Поэтому меряем, какой мировой
    /// длиной оборачивается рост на экране, и все поперечные размеры считаем
    /// от неё. Тогда доли роста выполняются там, где их видно: в кадре.
    private struct Anatomy {
        let x: Double
        let z: Double
        /// Рост в мировых единицах.
        let h: Double
        /// Мировая длина поперёк взгляда, дающая на экране целый рост.
        let span: Double
        let pose: Pose

        init(foot: (Double, Double), height: Double, pose: Pose,
             project: Solid3D.Projection)
        {
            x = foot.0
            z = foot.1
            h = height
            self.pose = pose
            let ground = project(foot.0, 0, foot.1)
            let crown = project(foot.0, -height, foot.1)
            span = abs(crown.0.y - ground.0.y) / max(ground.1, 0.0001)
        }

        /// Уровень плечевого сустава — от него растут все руки.
        var shoulder: Double { pose.hip + 0.288 }

        /// Точка разметки: вбок и вглубь — в долях роста, вверх — от пола.
        ///
        /// Поза набирает силу от таза к плечам и выше уже не растёт: гнётся
        /// спина, а шея сидит на плечах. Если продолжать наклон линейно вверх,
        /// голова уезжает тем дальше, чем она выше, и фигура ломается пополам.
        /// Руки и реквизит задаются теми же координатами, поэтому кисть,
        /// поставленная на клавиши, едет вместе с наклонившимся корпусом сама.
        func at(_ side: Double, _ level: Double, _ depth: Double = 0)
            -> (Double, Double, Double)
        {
            let bend = max(0, min(1, (level - pose.hip) / 0.288))
            return (x + (side + pose.roll * bend) * span,
                    -level * h,
                    z + (depth - (pose.lean + pose.twist * side) * bend) * span)
        }

        /// Точка, жёстко связанная с плечевым поясом: поза применяется к ней
        /// целиком, а не по высоте. Так задаются руки и всё, что фигура держит
        /// в руках. Через `at` рука ломается: локоть стоит ниже плеча, значит
        /// получает меньшую долю наклона, и чем круче поза, тем сильнее
        /// растягивается плечо — на отклонённом назад вокалисте оно выходило
        /// в полтора раза длиннее своего же предплечья.
        func held(_ side: Double, _ level: Double, _ depth: Double = 0)
            -> (Double, Double, Double)
        {
            (x + (side + pose.roll) * span,
             -level * h,
             z + (depth - pose.lean - pose.twist * side) * span)
        }

        /// Поперечный размер в долях роста.
        func size(_ fraction: Double) -> Double { fraction * span }
    }

    /// Корпус, ноги и голова. Всё, чем одна фигура отличается от другой в
    /// осанке и постановке ног, приходит из `figure.pose`.
    private func body(_ figure: Anatomy,
                      glow: Double,
                      density: Double = 0.52,
                      project: @escaping Solid3D.Projection,
                      line: Double) -> [Solid3D.Piece]
    {
        let material = ice(glow: glow, density: density)
        let pose = figure.pose
        var pieces: [Solid3D.Piece] = []

        // Пятно опоры считается по стопам, а не по точке фигуры. Носки вынесены
        // к зрителю почти на десятую роста, а расстановка разводит пятки вбок —
        // пятно под самой точкой до них не доставало, и ноги кончались за его
        // краем, отчего фигура стояла не на подиуме, а над ним.
        pieces.append(Solid3D.contactShadow(
            at: (figure.x, figure.z - figure.size(0.052)),
            radius: figure.size(0.155 + 0.085 * pose.stance),
            strength: 0.55, project: project))

        let hip = pose.hip
        // Сидящая фигура: таз опущен ниже середины роста, и бедро уходит
        // вперёд, а не вниз. Прямые ноги под опущенным тазом читались бы
        // как стоящий коротышка.
        let seated = hip < 0.42

        for side in [-1.0, 1.0] {
            // Расстановка ног — половина всей позы: на этой камере наклон
            // корпуса уходит в глубину и почти не виден, а разведённые ноги
            // и вынесенная вперёд стопа читаются поперёк экрана сразу.
            let wide = max(0.2, pose.stance + side * pose.brace)
            // Шаг задан по глубине: у правой ноги к зрителю, у левой от него.
            let step = side * pose.stride

            // Бедро толще голени, стык — на середине ноги: одна капсула
            // постоянной толщины давала ровную сосиску без колена.
            // Сидя колени разведены шире таза — сомкнутые ноги под опущенным
            // тазом сливаются в одну вертикальную палку.
            let knee = seated ? figure.at(side * 0.090 * wide, hip - 0.020, -0.230)
                              : figure.at(side * 0.045 * wide, 0.345, -step * 0.55)
            let ankle = seated ? figure.at(side * 0.082 * wide, 0.070, -0.250)
                               : figure.at(side * 0.038 * wide, 0.070, -step)
            // Стопа лежит на полу и развёрнута носком наружу. Камера смотрит
            // сверху, и чистая ось z проецируется в почти вертикальный отрезок:
            // стопа, уложенная строго вдоль неё, читалась не ступнёй, а
            // обрубком под голенью. Разворот носка даёт ей длину поперёк экрана.
            // Разворот носка наружу задан прибавкой, а не множителем: если
            // умножать на ширину расстановки, то у широко стоящей фигуры
            // носки разъезжаются вдвое сильнее пяток и стопы становятся
            // клоунскими. Прибавка держит угол разворота постоянным.
            //
            // Носок развёрнут сильнее прежнего, а вперёд уходит вдвое меньше.
            // Пропорция тут считается не в мире, а на экране: глубина ложится
            // круче высоты, поэтому вынесенная вперёд стопа на кадре просто
            // падает вниз, и на прежних числах она уходила вниз на 14 пикселей
            // при 3 в сторону. Голень над ней тоже вертикальна, стык читался
            // коленом, а вся фигура — присевшей: ниже пояса виднелись голень
            // со стопой, а глаз собирал из них бедро с голенью.
            let heel = seated ? figure.at(side * 0.078 * wide, 0.044, -0.236)
                              : figure.at(side * 0.040 * wide, 0.034, 0.014 - step)
            let toe = seated ? figure.at(side * (0.078 * wide + 0.034), 0.026, -0.340)
                             : figure.at(side * (0.040 * wide + 0.070), 0.023, -0.052 - step)

            // Тазобедренный сустав ширину расстановки не меняет: ноги
            // разъезжаются от таза, а не переносятся вбок целиком.
            pieces.append(Solid3D.capsule(
                from: figure.at(side * 0.050, hip), to: knee,
                radius: figure.size(0.048),
                material: material, project: project, lineWidth: line))
            pieces.append(Solid3D.capsule(
                from: seated ? figure.at(side * 0.088 * wide, hip - 0.045, -0.240)
                             : figure.at(side * 0.045 * wide, 0.300, -step * 0.75),
                to: ankle,
                radius: figure.size(0.032),
                material: material, project: project, lineWidth: line))
            pieces.append(Solid3D.capsule(
                from: heel, to: toe,
                radius: figure.size(0.025),
                material: material, project: project, lineWidth: line))
            // Пятка шаром: без неё стопа сзади срезана и голень упирается
            // в пол торцом капсулы.
            pieces.append(Solid3D.sphere(
                centre: heel, radius: figure.size(0.025),
                material: material, project: project, lineWidth: line))
            // Пятно под самой подошвой, вдобавок к общему под фигурой. Общее
            // раскинуто на всю расстановку и на тёмном полу читается разве что
            // краем, а сцепление с полом видно только там, где стопа его
            // касается. Сидящей фигуре оно не нужно: у неё ноги на педалях.
            if !seated {
                pieces.append(Solid3D.contactShadow(
                    at: ((heel.0 + toe.0) * 0.5, (heel.2 + toe.2) * 0.5),
                    radius: figure.size(0.078), strength: 1.45, project: project))
            }
        }

        // Корпус тремя обхватами: таз, талия, грудная клетка. Две одинаковые
        // капсулы давали бочку, а силуэт человека держится именно на перепаде
        // плечи — пояс — бёдра.
        pieces.append(Solid3D.capsule(
            from: figure.at(-0.040, hip + 0.010), to: figure.at(0.040, hip + 0.010),
            radius: figure.size(0.048),
            material: material, project: project, lineWidth: line))
        pieces.append(Solid3D.capsule(
            from: figure.at(0, hip + 0.075), to: figure.at(0, hip + 0.125),
            radius: figure.size(0.066),
            material: material, project: project, lineWidth: line))
        pieces.append(Solid3D.capsule(
            from: figure.at(0, hip + 0.195), to: figure.at(0, hip + 0.235),
            radius: figure.size(0.086),
            material: material, project: project, lineWidth: line))
        // Плечевой пояс отдельной поперечной капсулой — иначе ширина плеч
        // равна ширине груди и фигура выходит без разворота.
        pieces.append(Solid3D.capsule(
            from: figure.at(-0.074, figure.shoulder), to: figure.at(0.074, figure.shoulder),
            radius: figure.size(0.038),
            material: material, project: project, lineWidth: line))

        // Шея короткая, но её видно между плечами и подбородком.
        pieces.append(Solid3D.capsule(
            from: figure.at(0, hip + 0.275), to: figure.at(0, hip + 0.348),
            radius: figure.size(0.033),
            material: material, project: project, lineWidth: line))
        // Череп не шар: капсула даёт овал выше своей ширины — вместе с волосами
        // это 0.14 роста в высоту при 0.084 в ширину, то есть рост в семь голов.
        // Макушка вынесена по глубине, поэтому голова наклонена, а не поставлена
        // на шею отвесно: отвесная читалась безликой пилюлей.
        pieces.append(Solid3D.capsule(
            from: figure.at(0, hip + 0.392, pose.headTilt * 0.2),
            to: figure.at(0, hip + 0.436, pose.headTilt),
            radius: figure.size(0.042),
            material: material, project: project, lineWidth: line))
        // Шапка волос: шар чуть шире черепа, сдвинутый назад и вверх. На таком
        // размере головы никакая прорисовка не видна — виден только силуэт,
        // поэтому причёска сделана тем же, чем и всё остальное: массой. Камера
        // смотрит сверху, глубина уходит вверх по экрану, и масса ложится на
        // темя и затылок, оставляя спереди узкий подбородок. Поперечная капсула
        // на этом месте выходила за череп в обе стороны и читалась не причёской,
        // а полями шляпы, поэтому здесь именно шар.
        pieces.append(Solid3D.sphere(
            centre: figure.at(0, hip + 0.428, 0.022 + pose.headTilt * 0.6),
            radius: figure.size(0.046),
            material: material, project: project, lineWidth: line))
        // Прядь до шеи: она почти не меняет силуэт, но даёт затылку толщину,
        // и голова перестаёт быть симметричной пилюлей.
        pieces.append(Solid3D.capsule(
            from: figure.at(0, hip + 0.412, 0.034 + pose.headTilt * 0.6),
            to: figure.at(0, hip + 0.368, 0.028 + pose.headTilt * 0.4),
            radius: figure.size(0.026),
            material: material, project: project, lineWidth: line))

        return pieces
    }

    /// Рука: плечо толще предплечья, локоть на середине, на конце кисть.
    private func arm(_ figure: Anatomy,
                     shoulder: (Double, Double, Double),
                     elbow: (Double, Double, Double),
                     wrist: (Double, Double, Double),
                     glow: Double,
                     density: Double = 0.52,
                     project: @escaping Solid3D.Projection,
                     line: Double) -> [Solid3D.Piece]
    {
        let material = ice(glow: glow, density: density)
        // Кисть строится по продолжению предплечья: пясть тоньше него,
        // а кулак на конце толще. Раньше рука кончалась капсулой той же
        // толщины и читалась просто как удлинённое предплечье.
        func beyondWrist(_ fraction: Double) -> (Double, Double, Double) {
            (wrist.0 + (wrist.0 - elbow.0) * fraction,
             wrist.1 + (wrist.1 - elbow.1) * fraction,
             wrist.2 + (wrist.2 - elbow.2) * fraction)
        }
        return [
            // Плечевой сустав шаром. Без него капсула руки прирастает к корпусу
            // торцом, и стык виден изломом под неестественным углом — сустав
            // же сохраняет форму при любом развороте руки.
            Solid3D.sphere(centre: shoulder, radius: figure.size(0.040),
                           material: material, project: project, lineWidth: line),
            Solid3D.capsule(from: shoulder, to: elbow, radius: figure.size(0.033),
                            material: material, project: project, lineWidth: line),
            Solid3D.capsule(from: elbow, to: wrist, radius: figure.size(0.026),
                            material: material, project: project, lineWidth: line),
            Solid3D.capsule(from: wrist, to: beyondWrist(0.16), radius: figure.size(0.022),
                            material: material, project: project, lineWidth: line),
            Solid3D.sphere(centre: beyondWrist(0.34), radius: figure.size(0.030),
                           material: material, project: project, lineWidth: line),
        ]
    }

    // MARK: - Фигуры

    /// Пятно света на полу — не тень, а луч сверху, упавший на подиум.
    ///
    /// Источник у него теперь есть: два средних прожектора фермы целят как раз
    /// сюда, в переднюю треть, и это пятно — их общий след, подобранный под
    /// саму фигуру. Пока конусов не было, пятно под ногами читалось лужей
    /// без причины: свет на сцене обязан откуда-то приходить.
    ///
    /// `contactShadow` для этого не годится: у него светлый ореол только
    /// обрамляет тёмное ядро, потому что его дело — прижать предмет к полу
    /// в месте касания. Здесь нужно обратное — светлое поле шире самой фигуры,
    /// на котором фигура и стоит. Кладётся оно на плоскость пола: сплюснутость
    /// берётся у самой проекции, как и у пятна контакта, иначе луч на наклонной
    /// сцене читается кругом, висящим в воздухе.
    private func footlight(at position: (Double, Double), radius r: Double,
                           strength: Double,
                           project: Solid3D.Projection) -> Solid3D.Piece
    {
        let centre = project(position.0, 0, position.1)
        let screenRadius = max(r * centre.1, 0.001)
        let flatten = abs(project(position.0, 0, position.1 + r).0.y - centre.0.y) / screenRadius
        let disc = Path(ellipseIn: CGRect(x: centre.0.x - screenRadius,
                                          y: centre.0.y - screenRadius * flatten,
                                          width: screenRadius * 2,
                                          height: screenRadius * flatten * 2))
        // Глубина чуть больше пола: луч ложится под все тела фигуры, включая
        // её собственные пятна контакта, — иначе он забивает их светом.
        return Solid3D.Piece(depth: centre.2 + 0.002) { context in
            context.blendMode = .plusLighter
            context.fill(
                disc,
                with: .radialGradient(
                    // Гаснет к 0.82, а не к единице: заливка круглая, а пятно
                    // сплюснуто, и на его верхнем и нижнем краю раскладка иначе
                    // обрывается поперёк видимой полосой.
                    Gradient(stops: [
                        .init(color: Color(hue: 0.090, saturation: 0.50, brightness: 1)
                            .opacity(0.078 * strength), location: 0),
                        .init(color: Color(hue: 0.080, saturation: 0.62, brightness: 1)
                            .opacity(0.038 * strength), location: 0.45),
                        .init(color: .clear, location: 0.82),
                    ]),
                    center: centre.0, startRadius: 0, endRadius: screenRadius))
            context.blendMode = .normal
        }
    }

    private func vocalist(at foot: (Double, Double), height h: Double,
                          project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        // Поза вокалиста: корпус отклонён назад, вес на отставленной левой
        // ноге, правая вынесена вперёд, плечи развёрнуты вслед за вскинутой
        // рукой. Отклон назад тут важнее наклона: только он читается как
        // «поёт в потолок», а не «разглядывает пол».
        //
        // Движение: корпус ведёт вбок медленной волной, а на ударе певец
        // откидывается назад и подсаживается на ногах. Приседание задано ростом,
        // а не отдельным сдвигом: рост стягивает к полу всю фигуру разом —
        // и корпус, и руки, и микрофон, — тогда как сдвиг одного таза оторвал
        // бы плечи от рук, заданных в абсолютных уровнях.
        let sway = wave(0) * live
        let figure = Anatomy(foot: foot, height: h * (1 - 0.022 * beat),
                             pose: Pose(lean: -0.070 - 0.026 * beat,
                                        twist: 0.26 + 0.055 * sway,
                                        roll: -0.060 + 0.050 * sway,
                                        stance: 1.40, stride: 0.060,
                                        // Подбородок вверх на удар: певец тянет
                                        // ноту в потолок именно на сильной доле.
                                        headTilt: 0.032 + 0.020 * sway + 0.022 * beat),
                             project: project)
        // Певец — самая горячая фигура сцены и по накалу, и по плотности.
        // Он стоит впереди всех на самой тёмной части подиума, и никакого
        // предмета за спиной, на котором читался бы его силуэт, у него нет.
        let glow = 0.48 + 0.52 * energy
        let density = 0.64
        // Пятно света под ногами. С самим силуэтом на кадре всё в порядке:
        // тело даёт 130-180 против 30 у пола, вчетверо, — не видно другого,
        // на чём он стоит. Передний край подиума освещён слабее всего, пол там
        // почти чёрный, и ноги просто кончаются в пустоте. Пятно даёт им опору,
        // а заодно объясняет, почему фронтмен светится сильнее остальных: он
        // в луче. Свет от музыки и растёт — в тишине луч почти гаснет.
        var pieces = [footlight(at: (figure.x, figure.z - figure.size(0.040)),
                                radius: figure.size(0.62),
                                strength: 0.55 + 0.45 * energy, project: project)]
        pieces += body(figure, glow: glow, density: density, project: project, line: line)

        // Рука вскинута вверх и назад; на ударе поднимается ещё выше, а между
        // ударами качается вместе с корпусом — застывшая рука над качающимся
        // телом выглядит подвешенной на нитке.
        //
        // Локоть выведен наружу, а запястье возвращено внутрь: обе кости
        // раньше шли от плеча наружу одна за другой, и на локте набиралось
        // 22 градуса от прямой — рука читалась палкой с шариком на конце.
        // Теперь плечевая идёт вверх-наружу на 22 пикселя, предплечье
        // вверх-внутрь на 15, а излом на локте вырос до полусотни градусов.
        let lift = 0.03 + 0.06 * beat + 0.020 * sway
        let raisedElbow = figure.held(-0.240, 0.920, 0.030)
        let raisedWrist = figure.held(-0.210, 1.050 + lift, 0.040)
        pieces += arm(figure,
                      shoulder: figure.held(-0.078, 0.788),
                      elbow: raisedElbow,
                      wrist: raisedWrist,
                      glow: glow, density: density, project: project, line: line)
        // Разворот кисти. `arm` строит кисть по продолжению предплечья, и на
        // конце получается шарик, симметричный вокруг оси, — по нему не понять,
        // повёрнута ладонь или нет. Костяшки положены поперёк оси: масса
        // выходит за габарит предплечья вбок, и кисть читается развёрнутой
        // к залу, а не насаженной на палку.
        let fist = (raisedWrist.0 + (raisedWrist.0 - raisedElbow.0) * 0.34,
                    raisedWrist.1 + (raisedWrist.1 - raisedElbow.1) * 0.34,
                    raisedWrist.2 + (raisedWrist.2 - raisedElbow.2) * 0.34)
        let hand = ice(glow: glow, density: density + 0.08)
        pieces.append(Solid3D.capsule(
            from: (fist.0 - figure.size(0.030), fist.1 - 0.012 * figure.h, fist.2 - figure.size(0.020)),
            to: (fist.0 + figure.size(0.034), fist.1 - 0.004 * figure.h, fist.2 + figure.size(0.016)),
            radius: figure.size(0.019),
            material: hand, project: project, lineWidth: line))
        // Большой палец отдельным коротким телом с внутренней стороны: он и
        // отличает кисть от кулака-шарика, а разворот ладони виден именно по
        // тому, с какой стороны он торчит.
        pieces.append(Solid3D.capsule(
            from: (fist.0 + figure.size(0.020), fist.1 - 0.006 * figure.h, fist.2 + figure.size(0.010)),
            to: (fist.0 + figure.size(0.028), fist.1 + 0.026 * figure.h, fist.2 + figure.size(0.004)),
            radius: figure.size(0.014),
            material: hand, project: project, lineWidth: line))

        // Микрофон и рука, которая его держит. Микрофон задан первым: рука
        // ставится под него, а не наоборот. Кисть в `arm` вынесена за запястье
        // по оси предплечья, поэтому запястье считается обратным ходом от
        // локтя к хвату — тем же приёмом, что и хват гитариста.
        //
        // Место выбрано по фону, а не по анатомии. Предмет в пять пикселей
        // читается только там, где за ним пусто, а вокруг груди и плеча у
        // певца всё занято собственным телом: слева торс, снизу плечевой шар,
        // справа предплечье. Единственный чистый угол — справа от подбородка,
        // выше линии плеч, и микрофон поднят туда: головка идёт вдоль скулы,
        // корпус наискось вниз, и вся верхняя треть прибора лежит на голом
        // тёмном фоне.
        //
        // Плата за это — сложенная рука. Хват у лица приходит на экран в шести
        // пикселях от плечевого сустава при костях по пятнадцать, и рука
        // обязана сложиться вдвое: как локоть ни ставь, между плечевой и
        // предплечьем остаётся два десятка градусов. Выбран из них лучший
        // случай — локоть под рёбра и наружу, чтобы излом пришёлся на тёмный
        // фон, а не на силуэт корпуса.
        let micHeel = figure.held(0.163, 0.855, -0.080)
        let micHead = figure.held(0.078, 0.930, -0.035)
        func along(_ fraction: Double) -> (Double, Double, Double) {
            (micHeel.0 + (micHead.0 - micHeel.0) * fraction,
             micHeel.1 + (micHead.1 - micHeel.1) * fraction,
             micHeel.2 + (micHead.2 - micHeel.2) * fraction)
        }
        // Локоть висит у рёбер и вынесен наружу настолько, чтобы выйти из-за
        // силуэта корпуса: сустав, спрятанный за телом, не читается вовсе,
        // и рука тогда выходит одной прямой от плеча к лицу.
        let micElbow = figure.held(0.205, 0.655, 0.030)
        let grip = along(0.22)
        pieces += arm(figure,
                      shoulder: figure.held(0.078, 0.788),
                      elbow: micElbow,
                      wrist: (micElbow.0 + (grip.0 - micElbow.0) / 1.34,
                              micElbow.1 + (grip.1 - micElbow.1) / 1.34,
                              micElbow.2 + (grip.2 - micElbow.2) / 1.34),
                      glow: glow, density: density, project: project, line: line)

        // Ручной микрофон — короткое тело с шаром-головкой на конце, и узнаётся
        // он именно этой парой. Прежний был одной ровной спичкой: одиннадцать
        // пикселей в длину при двух с половиной в толщину, без головки и без
        // перепада по сечению, — и читался осколком стекла, воткнутым в шею.
        //
        // Микрофон светлее и холоднее фигуры: он на тёмном фоне, и держится
        // именно перепадом с ним. Тёмный прибор пробовали — на голом фоне он
        // пропадает начисто, а сделать его плотным и тёмным этот материал не
        // умеет: накладные слои идут в меру непрозрачности, и у тела толщиной
        // в два пикселя кромка на просвет занимает его целиком.
        //
        // Тел всего два: корпус и головка. Промежуточный перехват между ними
        // пробовал и убрал — три тела по два пикселя каждое дают три отдельных
        // кромки с провалами между ними, и микрофон читается не прибором,
        // а зигзагом осколков.
        // Насыщенность вдвое ниже, чем у льда фигуры, но не до нуля: совсем
        // обесцвеченный прибор выпадал из тёплой гаммы сцены серым пятном.
        let steel = Solid3D.Material(saturation: 0.44, glow: 0.40 + 0.30 * energy,
                                     opacity: 0.86)
        pieces.append(Solid3D.capsule(
            from: micHeel, to: along(0.80),
            radius: figure.size(0.014),
            material: steel, project: project, lineWidth: line))
        // Головка вчетверо шире корпуса: на пяти пикселях узнаётся именно этот
        // перепад, а не форма самой сетки.
        pieces.append(Solid3D.sphere(
            centre: micHead, radius: figure.size(0.030),
            material: steel, project: project, lineWidth: line))

        return pieces
    }

    private func guitarist(at foot: (Double, Double), height h: Double,
                           project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        // Поза гитариста: наклон вперёд над декой, вес на правой ноге, левая
        // отставлена вперёд и в упор, плечи развёрнуты к грифу — правое ушло
        // назад, левое вышло к зрителю, поэтому гриф сам поднимается
        // в кадре: разворот несёт с собой и гитару.
        //
        // Ноги стоят вразнобой, а не враспор. Ровная широкая расстановка на
        // этой камере читалась присядкой: обе ноги гнулись одинаково, таз
        // сидел низко, и человек выглядел усевшимся на невидимый стул. Стойка
        // узнаётся перекосом — правая нога идёт прямой линией из-под таза в
        // пол, левая вынесена вбок и вперёд. Вынос вперёд тут работает вдвойне:
        // глубина ложится на экран круче высоты, и отставленная стопа уходит
        // по кадру вниз на два десятка пикселей — шаг виден сразу.
        //
        // Движение: гитарист качается вперёд-назад над декой своей волной,
        // медленнее вокалиста, и кивает на ударе. Правая рука бьёт по струнам
        // втрое чаще качки — иначе рука ходит с корпусом заодно и удара по
        // струнам не видно вовсе.
        let sway = wave(2.1, rate: 0.85) * live
        let strum = wave(0.4, rate: 2.6) * live
        let fret = wave(1.3, rate: 1.6) * live
        // Общий с вокалистом подсед на удар: доля у группы одна, и просаживаться
        // на ней они должны вместе — врозь это читается не ритмом, а вознёй.
        let figure = Anatomy(foot: foot, height: h * (1 - 0.014 * beat),
                             pose: Pose(lean: 0.085 + 0.030 * sway,
                                        twist: -0.34 + 0.045 * sway,
                                        roll: 0.040 + 0.030 * sway,
                                        stance: 1.30, brace: -0.55, stride: -0.085,
                                        headTilt: -0.022 - 0.024 * beat),
                             project: project)
        // Накал у сидящих на подиуме поднят вслед за вокалистом: до сих пор
        // светились в основном их инструменты, а сами люди уходили в тон пола
        // и читались подставкой под гитару. Разница между музыкантами оставлена,
        // но отсчёт у всех троих ведётся выше.
        let glow = 0.38 + 0.52 * energy
        var pieces = body(figure, glow: glow, density: 0.56, project: project, line: line)

        // Гитара задана в собственных осях: `along` — вдоль инструмента от
        // центра нижней деки к головке грифа, `across` — поперёк него, `out` —
        // к зрителю от плоскости деки. Наклон грифа сидит в одной паре чисел,
        // поэтому инструмент доворачивается целиком, а не по детали за раз.
        //
        // Висит гитара как на ремне: дека у пояса с правой стороны, гриф поднят
        // к левому плечу примерно на двадцать градусов. Прежняя лежала поперёк
        // живота горизонтально и торчала вбок палкой.
        //
        // Уровень деки взят с поправкой на камеру: она смотрит сверху, и всё,
        // вынесенное к зрителю, съезжает по экрану вниз. Гитара прижата к
        // корпусу ближе прежнего именно поэтому: чем дальше она от живота,
        // тем ниже уползает по экрану, и заданная по животу оказывалась
        // на бедре.
        //
        // Поправку пришлось считать целиком, а не на глаз. Дека вынесена
        // к зрителю трижды: своим прижимом к животу, наклоном корпуса и
        // разворотом плеч — вместе это 0.21 span, а глубина ложится на экран
        // в 1.31 раза круче высоты. Итого гитара съезжала по кадру на 0.27
        // роста: заданная по животу, она приходила к коленям и накрывала
        // собой всю ногу от таза до голени. Ниже деки оставались голень со
        // стопой, и глаз собирал из них бедро с голенью — отсюда и присядка.
        // Уровень поднят ровно на эту поправку, и дека встаёт на кадре под
        // тазом, где ей и место.
        //
        // Заодно инструмент укорочен. Мерить его в долях роста тут бесполезно:
        // рост на экране сжат, а гитара лежит поперёк взгляда и не сжата вовсе.
        // Честная мерка — сам человек: у настоящей гитары длина равна двум с
        // небольшим ширинам плеч, а тут выходило три. Сжата ось целиком,
        // поэтому пропорции самого инструмента не поехали.
        let lift = 0.264, reach = 0.840
        func gtr(_ along: Double, _ across: Double = 0, _ out: Double = 0)
            -> (Double, Double, Double)
        {
            figure.held(-0.120 + along * reach - across * lift,
                        0.578 + along * lift + across * reach,
                        // Гриф уходит к зрителю: гитара развёрнута, а не
                        // приклеена к животу плашмя.
                        // Прижим к животу убавлен: половина экранного съезда
                        // набегала именно тут, а вынесенная вперёд дека ещё и
                        // висела в воздухе перед фигурой вместо того, чтобы
                        // лежать на ней.
                        -0.055 + out - along * 0.055)
        }

        // Обе кисти заданы в осях самой гитары, а не в осях фигуры: тогда любой
        // доворот инструмента уносит руки с собой и они не отрываются от струн.
        // Плечевая кость выдержана по канону, около 0.19 роста, а предплечью
        // столько не достаётся: гриф на этой камере проходит близко к плечу,
        // и от плеча до хвата всего треть вытянутой руки. Рука сложена, и
        // предплечье приходится держать коротким — иначе локоть уезжает
        // за середину груди. Правая ходит поперёк струн у бриджа, левая ползёт
        // вдоль грифа: это единственное, чем видна смена аккордов.
        // Кисть в `arm` вынесена за запястье по оси предплечья, поэтому хват
        // задаётся не запястьем, а точкой, куда должен прийти кулак: запястье
        // ставится на обратном ходу от локтя к ней. Иначе кисть промахивается
        // мимо струн ровно на свою длину — левая так и висела над грифом,
        // не касаясь его.
        func holdAt(_ target: (Double, Double, Double),
                    from elbow: (Double, Double, Double)) -> (Double, Double, Double)
        {
            (elbow.0 + (target.0 - elbow.0) / 1.34,
             elbow.1 + (target.1 - elbow.1) / 1.34,
             elbow.2 + (target.2 - elbow.2) / 1.34)
        }

        // Правая бьёт по струнам над нижней декой. Локоть заведён за спину,
        // а кисть вынесена к зрителю: на этой камере глубина ложится круче
        // высоты, и разница по глубине даёт предплечью экранную длину, которой
        // ему иначе не набрать — прежнее шло почти на камеру и от локтя до
        // кулака оставалось девять пикселей вместо четырнадцати.
        let strumElbow = figure.held(-0.230, 0.650 + 0.012 * strum, 0.030)
        let strumHand = gtr(0.020, -0.010 + 0.052 * strum, -0.065)
        pieces += arm(figure,
                      shoulder: figure.held(-0.078, 0.788),
                      elbow: strumElbow,
                      wrist: holdAt(strumHand, from: strumElbow),
                      glow: glow, density: 0.56, project: project, line: line)
        // Кулак у струн добавлен поверх руки и плотнее её. Дека — самое светлое
        // тело фигуры, и кисть той же прозрачности пропадала на ней начисто:
        // рука доходила до гитары и обрывалась. Плотный кулак читается на деке
        // силуэтом, а не просветом.
        pieces.append(Solid3D.sphere(
            centre: strumHand, radius: figure.size(0.033),
            material: ice(glow: glow, density: 0.76),
            project: project, lineWidth: line))
        // Левая рука пересекает гриф, а не лежит вдоль него: локоть висит ниже
        // линии грифа, кисть приходит на гриф сверху. Предплечье, уложенное
        // вдоль, сливалось с грифом в одну толстую конусную палку, и от гитары
        // оставалась пара дисков с рукой.
        //
        // Хват отодвинут от деки к середине грифа. У самой деки кисть попадает
        // в тот же ком, что верхняя дека, плечо и предплечье, и на кадре там
        // просто широкое светлое пятно; на открытом грифе, где за рукой один
        // тёмный пол, тот же кулак читается кулаком. Заодно предплечью хватает
        // длины: до ближнего лада оно не дотягивало и восьми пикселей.
        let fretAt = 0.395 + 0.040 * fret
        let fretElbow = figure.held(0.120, 0.640, -0.105)
        pieces += arm(figure,
                      shoulder: figure.held(0.078, 0.788),
                      elbow: fretElbow,
                      wrist: holdAt(gtr(fretAt, -0.010, 0.014), from: fretElbow),
                      glow: glow, density: 0.56, project: project, line: line)
        // Обхват: капсула наискось через гриф, от струн до тыльной стороны.
        // Один кулак, посаженный на ось грифа, читается шариком, положенным
        // на палку, — обхват виден только тогда, когда масса есть и перед
        // грифом, и за ним. Идёт она наискось, а не строго поперёк: пальцы
        // накрывают несколько ладов сразу, и на экране косая перекладина
        // расходится с почти горизонтальным грифом заметнее прямой.
        pieces.append(Solid3D.capsule(
            from: gtr(fretAt - 0.026, -0.014, -0.046),
            to: gtr(fretAt + 0.028, -0.004, 0.038),
            radius: figure.size(0.034),
            // Кисть на грифе плотнее остальной фигуры: на светлом грифе лёд
            // той же плотности растворяется, и от хвата остаётся утолщение
            // без границы.
            material: ice(glow: glow, density: 0.70),
            project: project, lineWidth: line))

        // Дерево корпуса плотное, в отличие от стеклянных фигур: сквозная дека
        // читалась мыльным пузырём на животе, а бледная — куском льда. Гитара
        // сделана того же густого золота, что бэклайн и барабаны.
        let wood = Solid3D.Material(saturation: 0.92, glow: 0.44 + 0.40 * air, opacity: 1.24)
        let neck = Solid3D.Material(saturation: 0.86, glow: 0.30 + 0.30 * air, opacity: 1.22)
        // Накладка грифа глуше самого грифа: по ширине на этой камере обе —
        // одна полоска в два пикселя, и различает их только перепад плотности.
        let board = Solid3D.Material(saturation: 0.98, glow: 0.05, opacity: 0.80)
        // Железо наоборот ярче дерева: бридж и звукосниматель лежат поверх
        // светлой деки, и тёмными они бы на ней просто пропали.
        let chrome = Solid3D.Material(saturation: 0.72, glow: 0.30 + 0.25 * air, opacity: 1.10)
        let steel = Solid3D.Material(saturation: 0.44, glow: 0.88, opacity: 0.90)
        let belt = Solid3D.Material(saturation: 0.90, glow: 0.10, opacity: 0.62)

        // Корпус — два диска разного размера, разнесённых вдоль оси. Заходят
        // они друг за друга примерно на треть меньшего радиуса: ровно настолько,
        // чтобы между обечайками осталась талия. Прежние стояли почти соосно
        // и сливались в один круг, от которого восьмёрки не оставалось.
        pieces.append(Solid3D.faceDisc(
            centre: gtr(0), radius: figure.size(0.104),
            material: wood, project: project, lineWidth: line, dish: 0.34))
        pieces.append(Solid3D.faceDisc(
            centre: gtr(0.150), radius: figure.size(0.078),
            material: wood, project: project, lineWidth: line, dish: 0.34))

        // Гриф с накладкой. Толщина взята от деки: у настоящей гитары гриф
        // уже корпуса раз в семь, и стоит сделать его вровень с рукой, как
        // инструмент читается уже не гитарой, а банджо с ручкой.
        pieces.append(Solid3D.capsule(
            from: gtr(0.190), to: gtr(0.455),
            radius: figure.size(0.015), material: neck,
            project: project, lineWidth: line))
        pieces.append(Solid3D.capsule(
            from: gtr(0.214, 0, -0.020), to: gtr(0.462, 0, -0.020),
            radius: figure.size(0.011), material: board,
            project: project, lineWidth: line))
        // Головка шире грифа, и на ней колки. Расширение на конце — то, чем
        // гриф отличается от палки, даже когда сами колки уже не разобрать.
        pieces.append(Solid3D.capsule(
            from: gtr(0.466, 0.008, -0.006), to: gtr(0.532, 0.018, -0.006),
            radius: figure.size(0.021), material: neck,
            project: project, lineWidth: line))
        for peg in [(-0.030, 0.480), (-0.030, 0.520), (0.030, 0.486), (0.030, 0.526)] {
            pieces.append(Solid3D.sphere(
                centre: gtr(peg.1, peg.0, -0.030), radius: figure.size(0.010),
                material: chrome, project: project, lineWidth: line))
        }

        // Бридж у нижнего края деки и звукосниматель на талии — поперечные
        // бруски по струнам. Сделаны они капсулами, а не коробками: коробка
        // не умеет наклоняться в плоскости кадра и легла бы на наклонённую
        // гитару горизонтально, поперёк собственных струн. Третий брусок,
        // как на настоящей электрогитаре, пробовался и убран: он ложится
        // ровно под бьющую кисть, а на деке в двадцать пикселей всё, что
        // закрыто рукой, работает не деталью, а грязью.
        for bar in [(-0.062, 0.042, 0.010), (0.078, 0.046, 0.012)] {
            pieces.append(Solid3D.capsule(
                from: gtr(bar.0, -bar.1, -0.030), to: gtr(bar.0, bar.1, -0.030),
                radius: figure.size(bar.2), material: chrome,
                project: project, lineWidth: line))
        }
        // Струны: три нити от бриджа до головки. Шесть на этой камере встают
        // теснее пикселя и сливаются в одну полосу — три дают ту же читаемую
        // натянутую связку и не мажут гриф.
        for offset in [-0.009, 0.0, 0.009] {
            pieces.append(Solid3D.capsule(
                from: gtr(-0.050, offset, -0.042), to: gtr(0.474, offset, -0.042),
                radius: figure.size(0.005), material: steel,
                project: project, lineWidth: line * 0.7))
        }
        // Ремень от верхнего рога к плечу: без него гитара приставлена к животу
        // и держится сама собой.
        pieces.append(Solid3D.capsule(
            from: gtr(0.196, 0.082, 0.020),
            to: figure.held(0.072, 0.812, 0.018),
            radius: figure.size(0.010), material: belt,
            project: project, lineWidth: line))

        return pieces
    }

    private func keyboardist(at foot: (Double, Double), height h: Double,
                             project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        // Поза клавишника: корпус подан к инструменту, ноги расставлены и одна
        // выдвинута вперёд. Наклон небольшой: глубокий над клавишами читается
        // уже как поклон.
        //
        // Сомкнутые ноги, стоявшие тут раньше, на этой камере пропадали внутри
        // собственной стойки: и голени, и трубы сходились к середине кадра в
        // одну точку, и ниже пояса клавишник читался торсом за столиком.
        // Расставленные ноги уводят голени из-под перекрестья, а шаг разносит
        // стопы по экрану вниз-вверх — только по ним и видно, что он стоит.
        //
        // Движение: корпус чуть ведёт над клавишами, а кисти бегают по ним
        // каждая своим темпом. Одинаковый ход обеих кистей читался бы игрой
        // на гармошке, поэтому темпы взяты несоизмеримые — руки расходятся
        // и сходятся не повторяясь.
        let sway = wave(4.2, rate: 0.9) * live
        let leftRun = wave(0.0, rate: 1.9) * live
        let rightRun = wave(2.6, rate: 2.7) * live
        // Нажатие: на ударе кисти оседают на клавиши. Ход маленький, но именно
        // он отличает игру от рук, положенных на инструмент. Считается он по
        // запястью, а кулак вынесен за него по оси предплечья и приходит с
        // рычагом — отсюда и такая мелкая величина: втрое больший ход утапливал
        // кисть в клавиатуру по запястье.
        let press = 0.010 * beat
        let figure = Anatomy(foot: foot, height: h * (1 - 0.010 * beat),
                             // Расстановка убавлена с 1.50: настолько широко
                             // ноги разводились, чтобы обойти прежнюю крестовину
                             // стойки, у которой узел приходился ровно на
                             // щиколотки. Крестовины больше нет — вместо неё
                             // козлы, и трубы у них проходят снаружи от стоп
                             // сами. А враспор клавишник и не стоит: за клавишами
                             // держатся, а не упираются, и широко расставленные
                             // ноги вместе с ногами стойки давали на кадре не
                             // человека, а паука.
                             pose: Pose(lean: 0.090 + 0.022 * sway, twist: 0.10,
                                        roll: 0.026 * sway, stance: 1.08,
                                        stride: 0.055,
                                        headTilt: -0.038 - 0.014 * beat + 0.012 * sway),
                             project: project)
        let glow = 0.36 + 0.50 * energy
        var pieces = body(figure, glow: glow, density: 0.56, project: project, line: line)

        // Руки разные: левая ушла в нижний край клавиатуры, правая играет
        // ближе к середине. Симметричные руки читались как стойка «смирно»
        // над инструментом — играют именно врозь.
        //
        // Локти разведены в стороны и отставлены назад, за линию плеча, а
        // запястье поднято к их уровню: в мире предплечье идёт над клавишами
        // почти горизонтально, как у живого клавишника. По экрану оно всё равно
        // падает — вынос к зрителю на этой камере съезжает вниз, и всякая
        // тянущаяся вперёд кость проецируется отвесно, — но излом на локте
        // виден, и рука перестала быть одной палкой от плеча до кулака.
        // Держится этот излом на разведении: плечо идёт вниз-наружу, предплечье
        // вниз-внутрь, и угол между ними появляется только пока локоть стоит
        // вбок дальше кисти. Прижатые к бокам локти его гасили начисто.
        //
        // Кисть ложится на клавиши к переднему краю ряда, а запястье остаётся
        // на дальнем. Играют именно там, в передней трети клавиши; заодно кулак
        // получает под собой тёмный передок корпуса — стеклянной кисти посреди
        // светлого ряда не видно вовсе, а на кромке она читается.
        //
        // Плотность у рук выше, чем у корпуса: кисть лежит на освещённом ряду
        // клавиш, и сквозная стеклянная рука на нём растворялась — от кулака
        // оставался один блик. Разница с корпусом на этом размере не видна,
        // а руки перестают тонуть и в самом торсе, поверх которого идут.
        let armDensity = 0.64
        pieces += arm(figure,
                      shoulder: figure.held(-0.078, 0.788),
                      elbow: figure.held(-0.185, 0.612, 0.022),
                      wrist: figure.held(-0.148 + 0.030 * leftRun, 0.6195 - press, -0.145),
                      glow: glow, density: armDensity, project: project, line: line)
        pieces += arm(figure,
                      shoulder: figure.held(0.078, 0.788),
                      elbow: figure.held(0.182, 0.618, 0.053),
                      wrist: figure.held(0.125 + 0.034 * rightRun, 0.6210 - press, -0.116),
                      glow: glow, density: armDensity, project: project, line: line)

        pieces += keyRig(figure, tall: h, project: project, line: line)

        return pieces
    }

    /// Инструмент клавишника: корпус с боковинами, ряд клавиш поверх и стойка
    /// козлами. Прежде тут лежала одна плита — по ней не видно ни клавиш,
    /// ни того, что она на чём-то стоит, и клавишник упирался руками в полку.
    ///
    /// Высота полки взята не по уровню, а по экрану. Камера смотрит сверху,
    /// и вынос инструмента на четверть роста к зрителю опускает его в кадре ещё
    /// на пятую часть роста: клавиатура, заданная по поясу, оказывается у колен.
    /// Поэтому клавиши стоят на 0.60 роста — почти по локоть, как высокая
    /// концертная стойка. На экране это приводит их к тазу, а не к бедру,
    /// и заодно освобождает ноги: чем выше инструмент, тем короче его силуэт
    /// в кадре и тем больше голени остаётся видно под ним.
    private func keyRig(_ figure: Anatomy, tall h: Double,
                        project: @escaping Solid3D.Projection,
                        line: Double) -> [Solid3D.Piece]
    {
        // Корпус того же густого золота, что бэклайн: прежняя серая плита
        // выпадала из гаммы и читалась куском пенопласта на палках.
        let shell = Solid3D.Material(saturation: 0.90, glow: 0.16 + 0.30 * air, opacity: 1.28)
        let cheek = Solid3D.Material(saturation: 0.84, glow: 0.24 + 0.34 * air, opacity: 1.28)
        // Клавиши светлее корпуса, но остаются золотом — белым на этой сцене
        // бывает только блик. Оба ряда притемнены `shade`, множителем яркости:
        // тон от него не меняется, темнеет одна яркость.
        //
        // Белым затемнение нужно ради рук: кулаки лежат на ряду стеклянными,
        // сквозь них видно сами клавиши, и на разогнанном ряду от кисти
        // оставался один блик. Ряд обязан быть темнее льда.
        //
        // Чёрным одного нулевого накала мало: яркость у этого материала идёт
        // от освещённости, и клавиша, поднятая над белыми, ловит свет передней
        // гранью — ряд загорался цепочкой рыжих огоньков ярче самих кулаков.
        // А различает ряды именно перепад тона: по размеру на этой камере
        // клавиша — три пикселя, и никакой формы у неё нет.
        let ivory = Solid3D.Material(saturation: 0.80, glow: 0.22 + 0.26 * air,
                                     opacity: 1.20, shade: 0.82)
        let ebony = Solid3D.Material(saturation: 0.98, glow: 0.02, opacity: 1.45, shade: 0.34)
        let rack = Solid3D.Material(saturation: 0.72, glow: 0.10 + 0.20 * air, opacity: 0.55)
        var pieces: [Solid3D.Piece] = []

        let span = figure.size(1)
        /// Точка инструмента: вбок и вглубь — в долях роста, вверх — от пола.
        ///
        /// Разметка идёт мимо позы: инструмент стоит на полу и качаться вместе
        /// с человеком за ним не должен. Раньше хватало `at` — вся стойка сидела
        /// ниже таза, где поза даёт ноль, — но клавиши поднялись выше таза,
        /// а оттуда `at` уже подмешивает наклон корпуса.
        func rig(_ side: Double, _ level: Double, _ depth: Double)
            -> (Double, Double, Double)
        {
            (figure.x + side * span, -level * figure.h, figure.z + depth * span)
        }

        pieces.append(Solid3D.contactShadow(at: (figure.x, figure.z - figure.size(0.245)),
                                            radius: figure.size(0.33),
                                            strength: 0.44, project: project,
                                            drift: 0.30))

        // Стойка козлами: две трубы сходятся под днищем корпуса и расходятся
        // вниз и наружу, к полозьям на полу. Перекрещены они у самой вершины,
        // под самым корпусом, и это не украшение: у честного креста в полную
        // ширину перекрестье приходится на середину высоты, а середина высоты
        // стойки на экране — это ровно щиколотки человека за ней. Ноги тонули
        // в узле, а не читались ногами. Разведённые же понизу трубы проходят
        // снаружи от стоп, и между ними остаётся чистый коридор под голени.
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.capsule(
                from: rig(-side * 0.030, 0.549, -0.208),
                to: rig(side * 0.265, 0, -0.245),
                radius: figure.size(0.0095), material: rack,
                project: project, lineWidth: line))
            // Полоз вдоль взгляда: труба, оборванная точкой, не стоит на полу.
            pieces.append(Solid3D.capsule(
                from: rig(side * 0.265, 0, -0.190),
                to: rig(side * 0.265, 0, -0.300),
                radius: figure.size(0.009), material: rack,
                project: project, lineWidth: line))
        }

        // Корпус и боковины. Боковины выше клавиш и выступают за них по глубине:
        // это те самые щёки, между которыми и сидит ряд, — без них клавиши
        // висят на плите открытым краем.
        pieces.append(Solid3D.box(
            centre: rig(0, 0.5695, -0.215),
            size: (figure.size(0.460), h * 0.046, figure.size(0.150)),
            material: shell, project: project, lineWidth: line))
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.box(
                centre: rig(side * 0.243, 0.5775, -0.218),
                size: (figure.size(0.032), h * 0.072, figure.size(0.162)),
                material: cheek, project: project, lineWidth: line))
        }

        // Ряд клавиш: девять белых поперёк корпуса и шесть чёрных между ними
        // в обычном порядке две-три. Порядок важен: равномерная гребёнка
        // читается решёткой радиатора, а провал на месте ми-фа и си-до —
        // клавиатурой.
        let pitch = 0.440 / 9
        for index in 0..<9 {
            pieces.append(Solid3D.box(
                centre: rig(-0.220 + pitch * (Double(index) + 0.5), 0.600, -0.247),
                size: (figure.size(pitch * 0.94), h * 0.015, figure.size(0.094)),
                // Обводка у клавиш тоньше общей: при полной она съедала саму
                // клавишу в три пикселя, и ряд читался штакетником.
                material: ivory, project: project, lineWidth: line * 0.7))
        }
        // Чёрные лежат на белых сверху, а не втоплены между ними вровень.
        // Порядок вывода тут решает всё: тела сортируются по глубине, а на
        // этой камере высота уходит в глубину сильнее выноса, и утопленный
        // ряд оказывался дальше белого — белые закрашивали чёрные целиком,
        // и от клавиатуры оставалась одна гребёнка светлых полос. Поднятые
        // на толщину белой клавиши, чёрные выходят ближе к зрителю и ложатся
        // поверх, как им и положено.
        for index in [0, 1, 3, 4, 5, 7] {
            pieces.append(Solid3D.box(
                centre: rig(-0.220 + pitch * Double(index + 1), 0.6185, -0.225),
                size: (figure.size(0.025), h * 0.022, figure.size(0.050)),
                material: ebony, project: project, lineWidth: line * 0.7))
        }

        return pieces
    }

    private func drummer(at foot: (Double, Double), height h: Double,
                         project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let glow = 0.38 + 0.55 * energy
        // Барабанщик сидит: таз на высоте стула, корпус наклонён к установке.
        // Рост берём больше h: h — это масштаб всего узла разом, а сидящий
        // человек одного роста с остальными должен быть выше своей посадки.
        // От этого роста считается и установка, поэтому она не может разъехаться
        // с человеком за ней: обе величины ходят одним множителем.
        // Поза барабанщика: спина подана вперёд, к установке, колени разведены
        // шире бочки — иначе ноги целиком тонут в её корпусе и сидящая фигура
        // читается торсом, приставленным к барабану.
        //
        // Движение: на ударе барабанщик кивает головой и подаётся к установке,
        // а руки бьют по очереди. Попеременность даёт одна волна, взятая с
        // разным знаком по сторонам: у левой руки замах там, где у правой удар.
        // Обе руки, поднимающиеся разом, читаются не игрой, а зарядкой.
        // Замах возведён в квадрат: рука дольше держится у пластика и уходит
        // вверх быстрее, чем возвращается. Чистая синусоида даёт ход маятника,
        // одинаковый вверху и внизу, а удар — это именно рывок из нижней точки.
        let stroke = wave(0, rate: 2.3)
        func hand(_ side: Double) -> Double {
            let swing = max(0, min(1, 0.5 + 0.5 * side * stroke))
            return swing * swing * live
        }
        let tall = h * 1.15
        let figure = Anatomy(foot: foot, height: tall,
                             // Плечи идут за руками: рука в замахе тянет свою
                             // сторону корпуса, и сидящая фигура перестаёт быть
                             // неподвижным пнём с шевелящимися руками.
                             // Разворот плеч в покое почти убран: он уносит одно
                             // плечо к зрителю, а на этой камере вынос к зрителю
                             // читается сдвигом вниз по экрану. Прежние 0.06
                             // держали плечи на разной высоте всегда, и сидящая
                             // фигура выглядела не развёрнутой, а перекошенной.
                             pose: Pose(lean: 0.115 + 0.030 * beat,
                                        twist: 0.020 + 0.055 * stroke * live, stance: 1.45,
                                        hip: 0.345, headTilt: -0.030 - 0.045 * beat),
                             project: project)
        var pieces = body(figure, glow: glow, density: 0.56, project: project, line: line)

        // Локти висят у рёбер, предплечья идут вперёд и чуть вверх, кисти
        // сходятся над серединой установки. Прежние руки были разведены на
        // ±0.238 роста при плечах в ±0.078 — на кадре это давало не барабанщика,
        // а чучело с крыльями: размах кистей втрое перекрывал ширину корпуса.
        // Дотягиваться до пластиков теперь не рука, а палочка — ей это и
        // положено. Кости при этом вышли канонными: плечевая 0.189 роста,
        // предплечье 0.154.
        //
        // Уровень кистей подобран по экрану: кулак должен приходить ВЫШЕ крышек
        // барабанов (на кадре это y около 400 при кулаке на 395), иначе рука
        // уходит за корпус переднего тома и от неё не остаётся ничего.
        // Локти отставлены от рёбер настолько, чтобы между рукой и поясом
        // остался просвет: прижатая рука на этой камере попадает в силуэт
        // корпуса целиком и перестаёт быть рукой — торс просто становится шире.
        // Просвет считается на уровне локтя, где корпус самый узкий (талия
        // 0.066 роста поперёк, локоть вынесен на 0.150).
        // Локоть отведён НАЗАД, а запястье вынесено вперёд — только на этой
        // паре у руки появляется излом на экране. Обе кости, направленные к
        // зрителю, проецируются почти отвесно и собираются в одну прямую
        // трубу от плеча до кулака: рука есть, а локтя нет. Отведённый назад
        // локоть уходит по экрану вверх, предплечье падает вниз — и на кадре
        // между ними набирается около двадцати градусов.
        for side in [-1.0, 1.0] {
            pieces += arm(figure,
                          shoulder: figure.held(side * 0.078, figure.shoulder),
                          elbow: figure.held(side * 0.150, 0.455, 0.060),
                          wrist: figure.held(side * 0.190, 0.505 + 0.030 * hand(side), -0.150),
                          glow: glow, density: 0.56, project: project, line: line)
        }

        pieces += drumKit(figure, tall: tall, project: project, line: line)

        // Палочки идут от кулаков вниз-наружу, на пластики. Цели выбраны не по
        // «правильному» хвату, а по экрану: крышка барабана должна приходить
        // ниже кулака, иначе палочка ложится на кадре вверх и читается усом.
        // Таких целей ровно две — малый слева и напольный справа; передние томы
        // вынесены к зрителю так далеко, что их крышки на кадре оказываются
        // ниже собственных ободов, но выше кистей, и удар по ним не читается.
        // Хват у каждой палочки задан своей точкой, а не общей формулой: кулак
        // сидит на продолжении предплечья (вбок 0.204, уровень 0.522, глубина
        // −0.221), и торец палочки отложен от него назад по её же оси. Общая
        // точка хвата на обе стороны давала палочку, торчащую из кисти сбоку:
        // цели у рук разные, значит и оси палочек расходятся. Правая палочка
        // длиннее левой и начинается прямо в кулаке: до напольного тома вдвое
        // дальше, чем до малого, и вынести её торец за кисть уже нечем — на
        // этом росте палочка и так выходит в четверть человека.
        //
        // Замах у каждой палочки свой — тот же попеременный ход, что и у
        // кистей, — а удар добавляет обеим общий подъём, потому что на сильную
        // долю бьют разом.
        let strikes: [(side: Double, grip: (Double, Double, Double),
                       tip: (Double, Double, Double))] = [
            (-1.0, (0.182, 0.547, -0.227), (0.345, 0.292, -0.185)),
            (1.0, (0.204, 0.522, -0.221), (0.428, 0.286, -0.295)),
        ]
        for strike in strikes {
            let raise = 0.014 + 0.115 * hand(strike.side) + 0.028 * beat
            // Хват поднимается слабее кончика: палочка не переносится вверх
            // целиком, а поворачивается в кисти, как оно и бывает при замахе.
            let lift = 0.040 * hand(strike.side)
            pieces.append(Solid3D.capsule(
                from: figure.held(strike.side * strike.grip.0,
                                  strike.grip.1 + lift, strike.grip.2),
                to: figure.held(strike.side * strike.tip.0,
                                strike.tip.1 + raise, strike.tip.2),
                radius: figure.size(0.015),
                // Палочка остаётся в гамме сцены. Прежние 0.34 насыщенности
                // при накале до единицы давали на сильной доле два белых
                // стержня — на золотой сцене они читались не деревом, а парой
                // включённых ламп, и взгляд уходил на них с самой установки.
                // Накал оставлен, но сдержанный: палочка на ударе подсвечивается,
                // а не загорается.
                material: Solid3D.Material(saturation: 0.62, glow: 0.22 + 0.26 * beat,
                                           opacity: 0.86, shade: 0.92),
                project: project, lineWidth: line))
        }

        return pieces
    }

    /// Установка целиком: бочка с лапами и педалью, томы на кронштейне,
    /// напольный том и малый на стойках, хай-хэт, райд и краш.
    ///
    /// Вся разметка идёт в долях роста барабанщика — поперёк через `figure.size`,
    /// вверх через сам рост. Прежняя установка мерилась мировыми единицами, и
    /// её поперечник на экране не имел никакого отношения к человеку за ней:
    /// бочка выходила вчетверо шире его плеч, а тарелки — с обеденное блюдо.
    /// Позы у установки нет намеренно: она стоит на полу, и качаться вместе
    /// с сидящим за ней человеком не должна.
    private func drumKit(_ figure: Anatomy, tall: Double,
                         project: @escaping Solid3D.Projection,
                         line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = (figure.x, figure.z)
        let unit = figure.size(1)

        // Барабаны почти непрозрачны, в отличие от фигур. У сквозного корпуса
        // видны разом все задние кромки, и установка читалась горстью мыльных
        // пузырей: у полупрозрачного цилиндра нет ни одного края, за который
        // глаз мог бы зацепиться как за границу тела.
        // Насыщенность у корпусов высокая — как у колонок портала. К свету она
        // и так падает почти вдвое (это заложено в материале), поэтому вялые
        // 0.5 давали на бликах бельё, а не золото: установка выходила серой
        // среди золотых музыкантов и колонок.
        let shell = Solid3D.Material(saturation: 0.86, glow: 0.32 + 0.50 * bass, opacity: 1.22)
        // Передний пластик бочки притемнён вдвое сильнее корпусов. Это самая
        // крупная плоскость установки, и она одна повёрнута к камере целиком:
        // на общем свету она выходила самым светлым пятном всей глубины сцены
        // и перетягивала взгляд с музыкантов на середину установки. Убавлен и
        // накал: у диска и так есть собственный блик от dish.
        let head = Solid3D.Material(saturation: 0.82, glow: 0.22 + 0.34 * bass,
                                    opacity: 1.20, shade: 0.76)
        // Два самых крупных корпуса — бочка и напольный том — притемнены
        // отдельно. Заливка граней у них та же, что у маленьких томов, но
        // площади вчетверо больше, и на общем свету они выходили двумя самыми
        // светлыми телами установки: глаз собирал кадр по ним, а не по человеку.
        let bulk = Solid3D.Material(saturation: 0.86, glow: 0.28 + 0.44 * bass,
                                    opacity: 1.22, shade: 0.88)
        // Железо стоек глушится непрозрачностью, а не тоном: у этого материала
        // яркость задаётся освещённостью, и притемнить трубку иначе нечем.
        // А глушить надо: тонких трубок в установке два десятка, и вместе они
        // дают больше света, чем все корпуса разом, — получался не бэклайн,
        // а моток проволоки, в котором где-то спрятаны барабаны.
        let metal = Solid3D.Material(saturation: 0.72, glow: 0.10 + 0.20 * air, opacity: 0.44)
        // Тарелки — самая жёлтая латунь на сцене: по цвету они и отличаются
        // от пластиков, потому что по форме на этой камере и то и другое круг.
        let brass = Solid3D.Material(saturation: 0.95, glow: 0.30 + 0.45 * air, opacity: 0.88)

        /// Точка установки: вбок и вглубь — в долях роста, вверх — от пола.
        func kit(_ across: Double, _ level: Double, _ depth: Double) -> (Double, Double, Double) {
            (x + across * unit, -level * tall, z + depth * unit)
        }
        /// Трубка железа между двумя точками разметки.
        func rod(_ from: (Double, Double, Double), _ to: (Double, Double, Double),
                 _ thickness: Double) -> Solid3D.Piece
        {
            Solid3D.capsule(from: kit(from.0, from.1, from.2), to: kit(to.0, to.1, to.2),
                            radius: unit * thickness, material: metal,
                            project: project, lineWidth: line)
        }
        /// Тренога под стойку. Ноги обязательно кончаются на нуле — это и есть
        /// пол; стойка, оборванная чуть выше, сразу выдаёт, что предмет
        /// нарисован, а не поставлен.
        func tripod(_ across: Double, _ depth: Double, hub: Double, reach: Double) -> [Solid3D.Piece] {
            (0..<3).map { index in
                let angle = Double(index) * 2.094 + 0.6
                return rod((across + sin(angle) * hub * 0.22, hub, depth + cos(angle) * hub * 0.22),
                           (across + sin(angle) * reach, 0, depth + cos(angle) * reach),
                           0.0075)
            }
        }
        /// Барабан: вертикальный цилиндр, сверху видна его же крышка-пластик.
        func drum(_ across: Double, _ level: Double, _ depth: Double,
                  radius: Double, depthHeight: Double) -> Solid3D.Piece
        {
            Solid3D.cylinder(centre: kit(across, level, depth), radius: unit * radius,
                             height: tall * depthHeight, material: shell,
                             project: project, lineWidth: line)
        }
        /// Тарелка. Сплюснутость взята под наклон камеры: она смотрит на сцену
        /// сверху, и лежащий круг даёт широкий эллипс, а не полоску. Прежние
        /// тарелки были сплюснуты вшестеро сильнее и читались не тарелками,
        /// а шляпками гвоздей, вбитых в воздух.
        func cymbal(_ across: Double, _ level: Double, _ depth: Double, _ radius: Double)
            -> Solid3D.Piece
        {
            Solid3D.faceDisc(centre: kit(across, level, depth), radius: unit * radius,
                             material: brass, project: project, lineWidth: line,
                             dish: 0.35, squash: 0.70)
        }

        var pieces: [Solid3D.Piece] = []

        // Общая тень под всей установкой. У неё много точек опоры — три ноги
        // на каждой стойке плюс лапы бочки, — и по отдельности ни одна из них
        // на подиуме не читается: тонкая трубка кончается в тон полу и с тем же
        // успехом могла бы кончиться на ладонь выше. Одно широкое пятно под
        // всем разом и прижимает установку к сцене.
        pieces.append(Solid3D.contactShadow(at: (x, z - 0.40 * unit), radius: unit * 0.68,
                                            strength: 0.42, project: project,
                                            drift: 0.30))

        // Стул. Барабанщику надо на чём-то сидеть: без стула таз висит в
        // воздухе и посадка читается не посадкой, а зависанием.
        // Сиденье шире таза, но глухое, как всё железо. Ярким его делать
        // нельзя: подсвеченный круг под самым животом читается не стулом,
        // а ещё одним барабаном, поставленным барабанщику на колени. Стул
        // должен опознаваться краями, выходящими из-под фигуры, и ногами —
        // а не собственной яркостью.
        pieces.append(Solid3D.cylinder(
            centre: kit(0, 0.288, 0.008), radius: unit * 0.106, height: tall * 0.030,
            material: metal, project: project, lineWidth: line))
        // Колонна стула тоньше прежней: она стоит ровно за фигурой и на просвет
        // проходит по ней сверху донизу тёмной чертой — стеклянный барабанщик
        // показывает сквозь себя всё, что за ним.
        pieces.append(rod((0, 0, 0.014), (0, 0.278, 0.014), 0.013))
        // Ноги стула разведены шире обычной треноги и развёрнуты одна назад,
        // две вперёд-вбок. Узкая тренога под стулом целиком тонет за бочкой:
        // на экране всё, что ниже её верхней кромки и уже её поперечника,
        // просто закрыто. Разведённые ноги выходят за край бочки — и стул
        // виден, а вместе с ним видно, что барабанщик сидит.
        for index in 0..<3 {
            let angle = Double(index) * 2.094
            pieces.append(rod((sin(angle) * 0.026, 0.150, 0.014 + cos(angle) * 0.026),
                              (sin(angle) * 0.172, 0, 0.014 + cos(angle) * 0.172),
                              0.008))
        }

        // Вся установка отодвинута от барабанщика к зрителю примерно на десятую
        // роста против прежней разметки. Это не про правдоподобие расстановки,
        // а про экран: вынос к зрителю на этой камере уводит предмет ВНИЗ, и
        // сдвинутая вперёд установка опускает свою верхнюю кромку с уровня
        // груди барабанщика на уровень его таза. Прежде корпуса стояли ровно
        // на середине человека, и от него оставались одна голова и плечи.
        //
        // Бочка лежит на боку, поэтому это капсула вдоль глубины, а не
        // вертикальный цилиндр: вертикальный давал барабан, поставленный
        // стоймя, и передняя мембрана висела на нём отдельным кругом.
        // Центр опущен так, чтобы низ обечайки почти касался пола: висящая
        // над сценой бочка выдаёт нарисованность вернее любой другой ошибки.
        pieces.append(Solid3D.contactShadow(at: (x, z - 0.64 * unit), radius: unit * 0.22,
                                            strength: 0.52, project: project))
        pieces.append(Solid3D.capsule(
            from: kit(0, 0.124, -0.520), to: kit(0, 0.124, -0.750),
            radius: unit * 0.138, material: bulk, project: project, lineWidth: line))
        pieces.append(Solid3D.faceDisc(
            centre: kit(0, 0.124, -0.756), radius: unit * 0.130,
            material: head, project: project, lineWidth: line, dish: 0.25))
        // Лапы: бочка без них не стоит, а лежит боком и норовит укатиться.
        // Пара упоров вперёд-вниз — то единственное, чем она держится.
        for side in [-1.0, 1.0] {
            pieces.append(rod((side * 0.132, 0.150, -0.610), (side * 0.238, 0, -0.720), 0.012))
        }
        // Педаль сдвинута от середины обода вправо, но не за его край: по
        // центру её целиком закрывает корпус бочки и от педали не остаётся
        // ничего, а вынесенная наружу она отрывается от барабана и читается
        // отдельным ящиком, поставленным рядом. На кромке видны и рама, и
        // колотушка, и при этом понятно, что они часть бочки.
        pieces.append(Solid3D.box(
            centre: kit(0.126, 0.017, -0.482),
            size: (unit * 0.072, tall * 0.030, unit * 0.120),
            material: metal, project: project, lineWidth: line))
        pieces.append(rod((0.126, 0.024, -0.532), (0.126, 0.140, -0.526), 0.010))
        pieces.append(Solid3D.sphere(
            centre: kit(0.126, 0.156, -0.524), radius: unit * 0.024,
            material: metal, project: project, lineWidth: line))

        // Томы висят на кронштейне из верха бочки — так их и держат на самом
        // деле. Отдельные стойки до пола пришлось бы вести сквозь корпус бочки.
        //
        // Томы разные и по калибру, и по высоте, и разведены в стороны сильнее
        // прежнего. Раньше это была симметричная пара одинаковых бочонков
        // впритык друг к другу: четыре похожих цилиндра в ряд читались одной
        // золотой массой, в которой ни один барабан не отличался от соседа.
        // Настоящие томы всегда идут по калибру — малый выше и уже, большой
        // ниже и шире, — и именно этот перепад различает их на кадре.
        // Просвет между ними подобран по ширине корпуса барабанщика: в него
        // видно человека от груди до бёдер, и установка перестаёт быть глухой
        // стеной перед ним.
        // Стойка кронштейна уведена с оси вбок. Настоящий держатель стоит по
        // центру бочки, но на этой камере центр установки — это и центр
        // барабанщика: отвесная трубка проходила ровно посередине фигуры и
        // разрезала её пополам сверху донизу.
        pieces.append(rod((0.052, 0.224, -0.610), (0.052, 0.508, -0.610), 0.012))
        pieces.append(rod((0.052, 0.508, -0.610), (-0.104, 0.512, -0.588), 0.010))
        pieces.append(rod((0.052, 0.508, -0.610), (0.108, 0.492, -0.600), 0.010))
        pieces.append(drum(-0.132, 0.500, -0.570, radius: 0.070, depthHeight: 0.112))
        pieces.append(drum(0.140, 0.468, -0.595, radius: 0.090, depthHeight: 0.128))

        // Напольный том: три ноги от середины корпуса к полу, как у него и есть.
        // Он самый крупный и самый глубокий из четырёх — по этому и опознаётся.
        pieces.append(Solid3D.contactShadow(at: (x + 0.428 * unit, z - 0.430 * unit),
                                            radius: unit * 0.17, strength: 0.40, project: project))
        for index in 0..<3 {
            let angle = Double(index) * 2.094 + 0.9
            pieces.append(rod((0.428 + sin(angle) * 0.110, 0.180, -0.430 + cos(angle) * 0.110),
                              (0.428 + sin(angle) * 0.144, 0, -0.430 + cos(angle) * 0.144),
                              0.011))
        }
        pieces.append(Solid3D.cylinder(
            centre: kit(0.428, 0.214, -0.430), radius: unit * 0.128, height: tall * 0.176,
            material: bulk, project: project, lineWidth: line))

        // Малый на треноге: колонка идёт от пола к корзине под самым корпусом.
        // Он широкий и плоский — обечайка вчетверо ниже, чем у томов. Это его
        // единственная примета: по диаметру он второй после напольного, и без
        // разницы в высоте корпуса на кадре выходил тем же бочонком.
        pieces += tripod(-0.345, -0.320, hub: 0.115, reach: 0.104)
        pieces.append(rod((-0.345, 0, -0.320), (-0.345, 0.272, -0.320), 0.013))
        pieces.append(drum(-0.345, 0.306, -0.320, radius: 0.108, depthHeight: 0.062))

        // Хай-хэт: две тарелки на одной стойке. Верхняя разводится с нижней
        // между ударами и захлопывается на доле — это единственное движение,
        // по которому пара тарелок читается хай-хэтом, а не сдвоенным крашем.
        let hats = 0.030 * (1 - beat) * live
        pieces += tripod(-0.560, -0.430, hub: 0.120, reach: 0.104)
        pieces.append(Solid3D.box(
            centre: kit(-0.560, 0.016, -0.362),
            size: (unit * 0.066, tall * 0.028, unit * 0.108),
            material: metal, project: project, lineWidth: line))
        pieces.append(rod((-0.560, 0, -0.430), (-0.560, 0.520, -0.430), 0.013))
        pieces.append(cymbal(-0.560, 0.500, -0.430, 0.092))
        pieces.append(rod((-0.560, 0.502, -0.430), (-0.560, 0.626 + hats, -0.430), 0.008))
        pieces.append(cymbal(-0.560, 0.570 + hats, -0.430, 0.096))

        // Райд справа и краш слева-сверху. Стойки наклонные: у прямой вертикали
        // тарелка сидит ровно на треноге и вся конструкция читается грибом.
        // Райд поднят выше прежнего: на кадре он ложился ровно на напольный том
        // и накрывал его крышку, а тарелка поверх барабана — это не установка,
        // а один непонятный предмет с двумя ободами.
        pieces += tripod(0.600, -0.440, hub: 0.130, reach: 0.112)
        pieces.append(rod((0.600, 0, -0.440), (0.530, 0.600, -0.552), 0.013))
        pieces.append(cymbal(0.530, 0.612, -0.560, 0.118))

        pieces += tripod(-0.780, -0.580, hub: 0.135, reach: 0.112)
        pieces.append(rod((-0.780, 0, -0.580), (-0.740, 0.786, -0.646), 0.012))
        pieces.append(cymbal(-0.740, 0.800, -0.650, 0.115))

        return pieces
    }

    /// Стек портала: сабвуфер на подставке и топ на нём, как на настоящей
    /// площадке. Один ящик читался тумбой у края сцены; узнаётся бэклайн
    /// именно стопкой — низ шире и глуше, верх уже и с рупором.
    ///
    /// `turn` разворачивает стек вокруг вертикали. Колонки на сцене всегда
    /// смотрят в зал через середину, и разворот внутрь даёт заодно объём:
    /// камере видны сразу фасад и щека кабинета, тогда как у ящика анфас
    /// видна одна грань, и он читается плоской карточкой.
    private func speaker(at foot: (Double, Double), height h: Double,
                         turn: Double,
                         project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        // Кабинет почти непрозрачен, в отличие от фигур: opacity здесь работает
        // множителем, и больше единицы он догоняет заливку граней до плотной.
        // У сквозного ящика видны все задние рёбра разом, и он читается пустым
        // каркасом; заодно глухая масса портала отделяет технику от стеклянных
        // музыкантов — по плотности, а не по цвету.
        // Портал притемнён: он бэклайн, а не солист. Глухая заливка граней
        // вывела его верхние плоскости в самое светлое пятно кадра, и два
        // ящика в углах перетягивали взгляд с музыкантов на себя.
        let cabinet = Solid3D.Material(saturation: 0.92, glow: 0.14 + 0.36 * bass,
                                       opacity: 1.30, shade: 0.70)
        // Диффузор темнее корпуса: светлый диск читался воздушным шаром,
        // вставленным в ящик, а не воронкой, утопленной в фасад.
        let cone = Solid3D.Material(saturation: 0.74, glow: 0.30 + 0.50 * bass,
                                    opacity: 1.15, shade: 0.74)
        // Щели порта и рупора: тот же корпусной тон, но темнее и без блеска —
        // светлые полосы читались накладками из белого пластика.
        let slot = Solid3D.Material(saturation: 0.80, glow: 0.22 + 0.40 * bass,
                                    opacity: 1.40, shade: 0.62)
        var pieces: [Solid3D.Piece] = []

        let cosTurn = cos(turn), sinTurn = sin(turn)
        /// Точка в осях самого стека: вбок по фасаду, уровень, вглубь от фасада.
        /// Всё тело задаётся здесь, поэтому разворот стека сам уносит с собой
        /// и динамики, и рупор — их не приходится доворачивать поштучно.
        func local(_ across: Double, _ level: Double, _ depth: Double) -> (Double, Double, Double) {
            (x + across * cosTurn + depth * sinTurn,
             level,
             z - across * sinTurn + depth * cosTurn)
        }

        // Железо подвеса: рамы и тяги между кабинетами. Тонкое и приглушённое —
        // на площадке это чёрный металл, и светиться ему нечем.
        let rig = Solid3D.Material(saturation: 0.70, glow: 0.08 + 0.18 * air,
                                   opacity: 0.62, shade: 0.66)

        // Тень уведена из-под стека: сверху ящик накрывает своё основание
        // целиком, и посаженная по центру она пропадала под ним без остатка —
        // портал висел в воздухе, хотя стоял на полу всеми четырьмя углами.
        pieces.append(Solid3D.contactShadow(at: (x, z), radius: h * 0.26,
                                            strength: 0.78, project: project,
                                            drift: 0.62))

        // Подкат под сабом: кабинет такого веса на площадке никогда не ставят
        // прямо на настил, под ним рама с колёсами.
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.024, 0),
            size: (h * 0.40, h * 0.048, h * 0.34),
            material: rig, project: project, lineWidth: line, yaw: turn))

        // Сабвуфер: единственное тело стека, которое стоит на полу. Он и
        // держит на себе всю башню, поэтому он самый широкий и глубокий.
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.185, 0),
            size: (h * 0.38, h * 0.275, h * 0.32),
            material: cabinet, project: project, lineWidth: line, yaw: turn))
        // Два порта на фасаде саба вместо динамика: у настоящего сабвуфера
        // наружу выходят щели фазоинвертора, а диффузор спрятан внутри.
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.box(
                centre: local(side * h * 0.098, -h * 0.185, -h * 0.157),
                size: (h * 0.105, h * 0.150, h * 0.022),
                material: slot, project: project, lineWidth: line, yaw: turn))
        }

        // Линейный массив: пять узких кабинетов один над другим, каждый
        // завален вперёд сильнее предыдущего. Так и вешают массив на любой
        // площадке: верхние ящики бьют в дальние ряды почти горизонтально,
        // нижние — под ноги первому ряду, и вся башня выгибается дугой.
        //
        // Дуга здесь и есть весь смысл замены: две коробки, поставленные одна
        // на другую, силуэта не имеют вовсе — это тумба. У массива силуэт
        // читается издали, и по нему видно, что это акустика, а не мебель.
        let boxes = 5
        var level = h * 0.325
        for index in 0..<boxes {
            let step = Double(index) / Double(boxes - 1)
            // Кабинеты кверху мельчают, но чуть-чуть. Сильный перепад ширины
            // давал ступенчатую башню — свадебный торт, а не массив: у него
            // силуэт сужается не ступенями, а разворотом ящиков.
            let tall = h * (0.106 - 0.014 * step)
            let wide = h * (0.330 - 0.030 * step)
            let deep = h * (0.150 - 0.016 * step)
            // Завал: нижний ящик уходит вперёд сильнее всех, верхний почти
            // отвесен. Так и вешают массив — нижние ящики бьют под ноги
            // первому ряду, верхние в дальние. Разброс здесь и делает силуэт:
            // на этой камере, смотрящей сверху, завал виден по тому, как
            // расходятся передние кромки, и веер читается лучше ступеней.
            let rake = -0.045 - 0.230 * (1 - step)

            let centre = level + tall / 2
            // Ящики массива темнее саба: их пять, и все они показывают камере
            // свою крышку. На общем тоне пять светлых плоскостей одна над
            // другой давали в углу кадра самое яркое пятно сцены — ярче
            // барабанов, ярче музыкантов.
            var arrayBox = cabinet
            arrayBox.shade = 0.56
            pieces.append(Solid3D.box(
                centre: local(0, -centre, 0),
                size: (wide, tall, deep),
                material: arrayBox, project: project, lineWidth: line,
                yaw: turn, pitch: rake))

            // Волновод на фасаде: узкая горизонтальная щель во всю ширину.
            // Круглый диффузор тут был бы враньём — у массива наружу смотрит
            // именно щель, и по ней он и узнаётся.
            pieces.append(Solid3D.box(
                centre: local(0, -centre, -deep * 0.46),
                size: (wide * 0.72, tall * 0.30, h * 0.016),
                material: slot, project: project, lineWidth: line,
                yaw: turn, pitch: rake))

            // Два динамика по краям щели — то, что у массива стоит по бокам
            // от волновода. Мелкие: на этом размере важно не показать их,
            // а не дать фасаду остаться голой плитой.
            for side in [-1.0, 1.0] {
                pieces.append(Solid3D.faceDisc(
                    centre: local(side * wide * 0.30, -centre, -deep * 0.52),
                    radius: tall * 0.26,
                    material: cone, project: project, lineWidth: line))
            }

            // Тяги между кабинетами: короткие стойки по бокам, которыми
            // ящики и сцеплены в башню. Без них массив рассыпается на
            // отдельные коробки, зависшие одна над другой.
            if index < boxes - 1 {
                for side in [-1.0, 1.0] {
                    pieces.append(Solid3D.capsule(
                        from: local(side * wide * 0.46, -(level + tall * 0.85), deep * 0.30),
                        to: local(side * wide * 0.44, -(level + tall * 1.18), deep * 0.26),
                        radius: h * 0.010, material: rig,
                        project: project, lineWidth: line))
                }
            }

            level += tall * 1.02
        }

        return pieces
    }

    // MARK: - Обвязка сцены
    //
    // Всё, чем площадка отличается от постамента с фигурами: стойки, мониторы,
    // кабели и свет над головами. Каждый предмет стоит на подиуме и связан
    // с кем-то из группы — обвязка читается не сама по себе, а тем, что она
    // объясняет, откуда у музыкантов звук.

    /// Железо обвязки: трубы стоек, рамы, кронштейны. Тот же приглушённый металл,
    /// что у стоек установки, — иначе десяток тонких трубок по всей сцене даёт
    /// вместе больше света, чем фигуры, и сцена превращается в моток проволоки.
    private var hardware: Solid3D.Material {
        // Железо тёмное и насыщенное: на площадке это чёрный крашеный металл,
        // и светиться ему нечем. Затемнение здесь заодно глушит и накладные
        // блики — иначе трубка в два пикселя состоит из одной кромки и
        // выходит светлее любого барабана.
        // Железо непрозрачное. Полупрозрачные трубки просвечивали друг сквозь
        // друга, и ферма с вышками читалась ворохом наложенных линий, сквозь
        // который видно и то, что за ним. У чёрного крашеного металла толщи
        // нет вовсе — сквозь него не идёт ничего.
        Solid3D.Material(saturation: 0.92, glow: 0.08 + 0.16 * air,
                         opacity: 1.12, shade: 0.50)
    }

    /// Микрофонная стойка с журавлём.
    ///
    /// Ставится не прямо перед лицом, а вполоборота сбоку: стойка перед
    /// фигурой ложится ровно на её силуэт, и обе читаются одним пятном.
    /// Журавль при этом заведён обратно к музыканту — по этому излому стойка
    /// и опознаётся стойкой, а не воткнутым в пол прутом.
    ///
    /// Камера смотрит сверху, поэтому всё, что вынесено к зрителю, съезжает
    /// по экрану вниз: микрофон, поставленный по мировому уровню рта, оказался
    /// бы в кадре у пояса. Отсюда и подъём журавля выше головы — на экране он
    /// приходит как раз к лицу.
    ///
    /// `phase` разводит качку двух стоек. Стойка на площадке никогда не стоит
    /// мёртво: колонна тонкая, журавль с микрофоном на отлёте, и её ведёт от
    /// того же баса, от которого качается вся сцена. Пока стойки стояли
    /// неподвижно среди качающихся людей, они читались не железом, а стойками
    /// от чертёжного прибора, воткнутыми в помост.
    private func micStand(base: (Double, Double), height h: Double,
                          boom: (Double, Double, Double),
                          phase: Double = 0,
                          project: @escaping Solid3D.Projection,
                          line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = base
        let metal = hardware
        // Ход задан на конце журавля, а не в колонне: гнётся всё сооружение
        // целиком, но видно этот изгиб только там, где плечо длиннее всего.
        // Медленнее людей вдвое — железо тяжелее и отзывается лениво.
        let flex = wave(phase, rate: 0.6) * live * h * 0.011
        // Микрофон светлее железа: это единственная деталь стойки, которую
        // на таком размере видно как предмет, а не как линию. Но разогнать его
        // ярче нельзя — стойка тонкая и тусклая, и раскалённая головка на её
        // конце отрывается от неё, повисая в воздухе отдельной блёсткой.
        let capsuleHead = Solid3D.Material(saturation: 0.78, glow: 0.24 + 0.30 * energy,
                                           opacity: 0.80)
        var pieces: [Solid3D.Piece] = []

        pieces.append(Solid3D.contactShadow(at: (x, z), radius: h * 0.11,
                                            strength: 0.38, project: project))

        // Тренога. Ноги обязательно кончаются на нуле: труба, оборванная выше
        // пола, сразу выдаёт, что предмет не поставлен, а нарисован.
        // Вынос ног убавлен: пятно треноги спорило по площади с самим человеком
        // рядом — она выходила шире его плеч и вдвое шире расстановки его стоп,
        // и рядом с клавишником стояла не стойка, а тренога от геодезического
        // прибора. Заодно убавлена и колонна: труба толщиной в плечевую кость
        // читалась не железом, а третьей рукой.
        for index in 0..<3 {
            let angle = Double(index) * 2.094 + 0.5
            pieces.append(Solid3D.capsule(
                from: (x + sin(angle) * h * 0.012, -h * 0.058, z + cos(angle) * h * 0.012),
                to: (x + sin(angle) * h * 0.070, 0, z + cos(angle) * h * 0.070),
                radius: h * 0.0065, material: metal, project: project, lineWidth: line))
        }

        let neck = (x + flex * 0.35, -h * 0.74, z)
        pieces.append(Solid3D.capsule(
            from: (x, -h * 0.045, z), to: neck,
            radius: h * 0.013, material: metal, project: project, lineWidth: line))
        // Барашек на изломе: без него журавль прирастает к колонне торцом
        // и стойка ломается пополам ровно там, где у настоящей сустав.
        pieces.append(Solid3D.sphere(
            centre: neck, radius: h * 0.021,
            material: metal, project: project, lineWidth: line))

        let head = (neck.0 + boom.0 + flex, neck.1 + boom.1, neck.2 + boom.2)
        pieces.append(Solid3D.capsule(
            from: neck, to: head,
            radius: h * 0.012, material: metal, project: project, lineWidth: line))
        // Держатель и сам микрофон — короткая капсула, довёрнутая от журавля
        // вниз, к лицу. Продолжение журавля тем же направлением читалось бы
        // просто удлинённой трубой, задранной в потолок: журавль идёт вверх,
        // а микрофон на его конце обязан смотреть вниз, на человека.
        let tip = (head.0 + boom.0 * 0.34, head.1 + h * 0.030, head.2 + boom.2 * 0.30)
        pieces.append(Solid3D.capsule(
            from: head, to: tip,
            radius: h * 0.017, material: capsuleHead, project: project, lineWidth: line))

        return pieces
    }

    /// Напольный монитор: клин у края подиума, развёрнутый к музыкантам.
    ///
    /// Клин собран из плинтуса и заваленного назад кабинета. Одним заваленным
    /// ящиком его не сделать: у наклонного тела нижняя кромка уходит под пол
    /// одним углом и висит над ним другим, а плинтус даёт монитору честное
    /// плоское дно, на котором он и стоит.
    ///
    /// `turn` доворачивает клин к середине сцены — мониторы всегда смотрят на
    /// того, кто над ними поёт, а не в зал.
    ///
    /// `rake` — угол завала панели. Он вынесен в параметры не ради точности,
    /// а ради непохожести: клинья на площадке никто не выставляет по линейке,
    /// их таскают ногой, и три штуки с одним и тем же завалом читаются одним
    /// предметом, размноженным по дуге.
    private func monitor(at foot: (Double, Double), width w: Double, turn: Double,
                         rake: Double = 0.46,
                         project: @escaping Solid3D.Projection,
                         line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let cabinet = Solid3D.Material(saturation: 0.92, glow: 0.14 + 0.34 * bass,
                                       opacity: 1.30, shade: 0.74)
        let cone = Solid3D.Material(saturation: 0.74, glow: 0.28 + 0.46 * bass,
                                    opacity: 1.15, shade: 0.78)
        var pieces: [Solid3D.Piece] = []

        pieces.append(Solid3D.contactShadow(at: (x, z), radius: w * 0.58,
                                            strength: 0.58, project: project,
                                            drift: 0.55))

        // Клин низкий и глубокий: чем он ниже, тем меньше в силуэте вертикального
        // торца и тем больше скошенной панели — а узнаётся монитор именно ею.
        // Заваленный ящик не может стоять на полу плоско: одна его нижняя кромка
        // уходит под сцену, другая висит над ней. Плоское дно даёт плинтус, а
        // завалённый корпус садится на него сверху.
        /// Точка в осях самого клина: вбок по фасаду, уровень, вглубь от фасада.
        /// Через неё же считается и динамик, поэтому доворот корпуса уносит
        /// его с собой, а не оставляет висеть над сценой отдельным кругом.
        func local(_ across: Double, _ level: Double, _ depth: Double) -> (Double, Double, Double) {
            (x + across * cos(turn) + depth * sin(turn),
             level,
             z - across * sin(turn) + depth * cos(turn))
        }

        // Плинтус уже и мельче корпуса: выступая из-под него, он читается не
        // подставкой, а второй ступенькой, и клин выходит комодом в две полки.
        let tilt = rake
        pieces.append(Solid3D.box(
            centre: local(0, -w * 0.035, -w * 0.020),
            size: (w * 0.90, w * 0.07, w * 0.50),
            material: cabinet, project: project, lineWidth: line, yaw: turn))
        pieces.append(Solid3D.box(
            centre: local(0, -w * 0.215, w * 0.045),
            size: (w * 0.94, w * 0.30, w * 0.58),
            material: cabinet, project: project, lineWidth: line, yaw: turn, pitch: tilt))

        // Панель клина отделана как у портала: волновод щелью поперёк, два
        // мелких динамика по краям и ручка сбоку. Один большой круг посреди
        // крышки читался конфоркой, и три клина в ряд выходили тремя плитами;
        // щель же роднит их с массивом — на площадке это и правда один
        // комплект, только один ящик висит, а другой лежит.
        //
        // Уровень панели: местная вертикаль, заваленная тем же углом, поэтому
        // всё, что на неё ложится, само уезжает вслед за наклоном корпуса
        // и не остаётся лежать плашмя на крыше.
        func onPanel(_ across: Double, _ out: Double) -> (Double, Double, Double) {
            let lift = w * 0.150 + out
            return local(across, -w * 0.215 - lift * cos(tilt), w * 0.045 + lift * sin(tilt))
        }

        var faceplate = cabinet
        faceplate.shade = 0.52
        pieces.append(Solid3D.box(
            centre: onPanel(0, -w * 0.010),
            size: (w * 0.76, w * 0.030, w * 0.34),
            material: faceplate, project: project, lineWidth: line,
            yaw: turn, pitch: tilt))

        var horn = cone
        horn.shade = 0.60
        pieces.append(Solid3D.box(
            centre: onPanel(0, w * 0.006),
            size: (w * 0.40, w * 0.028, w * 0.115),
            material: horn, project: project, lineWidth: line,
            yaw: turn, pitch: tilt))

        // Динамики по обе стороны от волновода. Щель была шире и накрывала
        // левый: на панели оставался один динамик справа, и клин выходил
        // несимметричным — не устройством, а склейкой.
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.faceDisc(
                centre: onPanel(side * w * 0.290, w * 0.008),
                radius: w * 0.110, material: cone, project: project,
                lineWidth: line, dish: 0.42, squash: 0.62))
        }

        // Ручка на торце: по ней и видно, что ящик носят руками. Мелочь,
        // но именно такие мелочи отличают аппарат от бруска.
        var grip = Solid3D.Material(saturation: 0.70, glow: 0.08 + 0.16 * air,
                                    opacity: 0.62, shade: 0.62)
        grip.liteHue = 0.086
        pieces.append(Solid3D.capsule(
            from: local(-w * 0.470, -w * 0.230, -w * 0.120),
            to: local(-w * 0.470, -w * 0.230, w * 0.120),
            radius: w * 0.026, material: grip, project: project, lineWidth: line))

        return pieces
    }

    /// Кофр с бутылкой воды на крышке.
    ///
    /// Передняя треть подиума — единственное пустое место кадра, и заполнять
    /// её приходится не декором, а тем, что на площадке у кромки действительно
    /// валяется. Кофр здесь работает ещё и меркой: ящик по колено и бутылка
    /// в ладонь дают передней трети масштаб, которого у голого пола нет, —
    /// без них рост людей в глубине не с чем сравнить.
    ///
    /// Ящик тёмный: он ближе всех к зрителю, а самый близкий предмет на этой
    /// камере ещё и самый крупный. Светлый кофр у кромки перетянул бы на себя
    /// весь передний план, ради которого его и ставят.
    private func roadCase(at foot: (Double, Double), width w: Double, turn: Double,
                          project: @escaping Solid3D.Projection,
                          line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let shell = Solid3D.Material(saturation: 0.94, glow: 0.10 + 0.20 * bass,
                                     opacity: 1.30, shade: 0.58)
        // Окантовка и ручка светлее корпуса: у настоящего кофра это алюминий
        // по рёбрам фанеры, и опознаётся ящик именно им. Без светлой рамки
        // тёмный параллелепипед у кромки читается дырой в подиуме.
        let trim = Solid3D.Material(saturation: 0.62, glow: 0.18 + 0.26 * bass,
                                    opacity: 1.20, shade: 0.86)
        // Бутылка — единственное на сцене, что почти не окрашено: вода
        // прозрачна, и по этой бесцветной вертикали её и видно на тёмной крышке.
        let water = Solid3D.Material(saturation: 0.26, glow: 0.34 + 0.34 * energy,
                                     opacity: 0.62)
        var pieces: [Solid3D.Piece] = []

        func local(_ across: Double, _ level: Double, _ depth: Double) -> (Double, Double, Double) {
            (x + across * cos(turn) + depth * sin(turn),
             level,
             z - across * sin(turn) + depth * cos(turn))
        }

        pieces.append(Solid3D.contactShadow(at: (x, z), radius: w * 0.52,
                                            strength: 0.62, project: project,
                                            drift: 0.58))
        // Ящик высокий и короткий по глубине. Низкий и широкий на этой камере
        // читался четвёртым клином: у монитора ровно тот же силуэт — плоская
        // светлая крыша и тёмный передок, — и в переднем ряду вместо трёх
        // одинаковых предметов выходило четыре.
        let high = w * 0.68
        // Корпус и крышка — два отдельных тела одного материала, а не ящик
        // с накладной полосой. Полоса тут не работает: плоская плита из тех же
        // граней показывает камере сверху всю свою крышу разом, и на месте
        // тонкой окантовки выходит светлая плоскость во весь ящик. Шов между
        // двумя телами даёт то же самое одной линией — и не даёт лишней грани,
        // ловящей свет.
        pieces.append(Solid3D.box(
            centre: local(0, -high * 0.36, 0), size: (w, high * 0.72, w * 0.64),
            material: shell, project: project, lineWidth: line, yaw: turn))
        pieces.append(Solid3D.box(
            centre: local(0, -high * 0.86, 0), size: (w * 0.98, high * 0.28, w * 0.62),
            material: shell, project: project, lineWidth: line, yaw: turn))
        // Ручка — единственный светлый металл на ящике, и она нарочно мелкая:
        // у любой грани этого рендера верх ловит полный свет, и светлое тело
        // крупнее ладони сразу выходит ярче портала.
        // Угловые башмаки к ней просились, но не выжили: два кубика по дальним
        // рёбрам на кадре целиком закрыты самим ящиком, а тела в общую
        // сортировку идут независимо от того, видно их или нет.
        pieces.append(Solid3D.capsule(
            from: local(-w * 0.30, -high * 0.44, -w * 0.33),
            to: local(w * 0.08, -high * 0.44, -w * 0.33),
            radius: w * 0.035, material: trim, project: project, lineWidth: line))

        // Бутылка стоит на крышке, а не на полу: на полу она в четыре пикселя
        // высотой и теряется в фактуре подиума, а на тёмной крышке кофра у неё
        // есть собственный фон.
        // Бутылка нарочно великовата против ящика. Камера сжимает высоту вдвое,
        // и честная поллитровка рядом с кофром по колено даёт на экране четыре
        // пикселя — пятно, а не предмет. Здесь она в треть ящика: это уже
        // неправда по размеру, но единственный способ показать, что на крышке
        // что-то стоит.
        let bottle = local(-w * 0.26, -high, w * 0.10)
        pieces.append(Solid3D.capsule(
            from: (bottle.0, bottle.1 - w * 0.085, bottle.2),
            to: (bottle.0, bottle.1 - w * 0.360, bottle.2),
            radius: w * 0.085, material: water, project: project, lineWidth: line))
        pieces.append(Solid3D.sphere(
            centre: (bottle.0, bottle.1 - w * 0.430, bottle.2), radius: w * 0.058,
            material: trim, project: project, lineWidth: line))

        return pieces
    }

    /// Смотанный кольцом жгут кабеля, брошенный у кромки, и его хвост.
    ///
    /// Кольцо из семи звеньев, а не из двенадцати: на экране у бухты диаметр
    /// в три десятка пикселей, и семиугольник от круга там не отличить, а
    /// каждое лишнее звено — отдельное тело в общей сортировке.
    /// Жгут заметно толще одиночного шнура: это связка проводов, и по толщине
    /// она и отличается от той нитки, что идёт от гитары к порталу.
    private func cableCoil(at foot: (Double, Double), radius r: Double, gauge: Double,
                           tail: (Double, Double),
                           project: @escaping Solid3D.Projection,
                           line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let rubber = Solid3D.Material(saturation: 0.96, glow: 0.04, opacity: 0.56)
        // Кольцо лежит на полу, поэтому его уровень — собственный радиус жгута,
        // а не ноль: бухта, посаженная в пол по центру, наполовину утоплена
        // в подиум и читается вдавленной в него канавкой.
        let level = -gauge
        var pieces: [Solid3D.Piece] = []

        // Не кольцо, а полтора витка спирали: радиус к концу подбирается,
        // виток уходит внутрь и наезжает на начало. Замкнутое кольцо ровного
        // радиуса читалось выточенной шайбой, а смотанный кабель узнаётся
        // именно тем, что виток лежит на витке. Сплюснуто поперёк взгляда:
        // правильный круг на этой камере опять же выходит деталью станка.
        let links = 8
        let turns = 1.45
        func ring(_ step: Double) -> (Double, Double, Double) {
            let angle = step * turns * 2 * .pi
            let coil = r * (1 - 0.20 * step)
            return (x + cos(angle) * coil,
                    level - step * gauge * 1.1,
                    z + sin(angle) * coil * 0.72)
        }
        for index in 0..<links {
            pieces.append(Solid3D.capsule(
                from: ring(Double(index) / Double(links)),
                to: ring(Double(index + 1) / Double(links)),
                radius: gauge, material: rubber, project: project, lineWidth: line * 0.7))
        }

        // Хвост уходит из бухты к соседнему предмету. Без него кольцо лежит
        // само по себе и читается обручем: кабель узнаётся тем, что у него
        // есть куда идти. Выходит хвост из обода, а не из середины: пущенный
        // от центра, он режет кольцо пополам и вся бухта читается перечёркнутой.
        let mouth = ring(0)
        let steps = 3
        for index in 0..<steps {
            let t0 = Double(index) / Double(steps), t1 = Double(index + 1) / Double(steps)
            func run(_ t: Double) -> (Double, Double, Double) {
                // Небольшой изгиб поперёк трассы: брошенный кабель не лежит
                // по линейке. Больше трети радиуса бухты давать нельзя:
                // на крутой дуге последнее звено выходит на экране почти
                // отвесным, и хвост читается не проводом, а подпоркой,
                // приставленной к клину.
                let bend = sin(t * .pi) * r * 0.30
                return (mouth.0 + (tail.0 - mouth.0) * t + bend,
                        level, mouth.2 + (tail.1 - mouth.2) * t - bend * 0.5)
            }
            pieces.append(Solid3D.capsule(from: run(t0), to: run(t1), radius: gauge,
                                          material: rubber, project: project,
                                          lineWidth: line * 0.7))
        }

        return pieces
    }

    /// Кабель: провисающая дуга из тонких капсул.
    ///
    /// Дуга задана квадратичной кривой, у которой опорная точка лежит ниже
    /// обоих концов, — так провод провисает собственным весом, а не идёт
    /// натянутой струной. Кончается кабель на полу, поэтому провис берётся
    /// не больше половины подъёма: иначе середина дуги уходит под сцену.
    private func cable(from start: (Double, Double, Double),
                       to end: (Double, Double, Double),
                       bow: Double, hang: Double, gauge: Double,
                       project: @escaping Solid3D.Projection,
                       line: Double) -> [Solid3D.Piece]
    {
        // Провод глухой и тёмный: это единственное на сцене, что не должно
        // светиться вовсе — светящийся кабель читается лучом, а не резиной.
        // Непрозрачность держит и накладные слои стекла, поэтому она у провода
        // низкая: при плотной заливке тонкая капсула набирает столько кромки
        // на просвет, что шнур выходит светлее самой гитары.
        let rubber = Solid3D.Material(saturation: 0.96, glow: 0.02, opacity: 0.50)
        // Изгиб вбок берётся по нормали к трассе в плане: без него кабель
        // лежит по линейке от гнезда до колонки и выглядит проложенным
        // по чертежу.
        let dx = end.0 - start.0, dz = end.2 - start.2
        let run = max(0.0001, (dx * dx + dz * dz).squareRoot())
        let control = ((start.0 + end.0) / 2 - dz / run * bow,
                       (start.1 + end.1) / 2 + hang,
                       (start.2 + end.2) / 2 + dx / run * bow)

        func point(_ t: Double) -> (Double, Double, Double) {
            let inv = 1 - t
            return (inv * inv * start.0 + 2 * inv * t * control.0 + t * t * end.0,
                    inv * inv * start.1 + 2 * inv * t * control.1 + t * t * end.1,
                    inv * inv * start.2 + 2 * inv * t * control.2 + t * t * end.2)
        }

        // Толщина задана снаружи и одна на все провода: если считать её от
        // длины трассы, длинный прогон выходит толще короткого — от гитары
        // к порталу шёл бы не шнур, а пожарный рукав.
        // Шесть звеньев, а не девять: на этой длине дуга и так гладкая, а каждое
        // звено — отдельное тело в общей сортировке, и три провода стоили сцене
        // почти десятой доли всех её тел.
        let steps = 6
        return (0..<steps).map { index in
            let a = point(Double(index) / Double(steps))
            let b = point(Double(index + 1) / Double(steps))
            return Solid3D.capsule(from: a, to: b, radius: gauge,
                                   material: rubber, project: project, lineWidth: line * 0.7)
        }
    }

    /// Ферма со светом позади группы: две стойки, решётчатая балка между ними
    /// и прожекторы под нею.
    ///
    /// Ферма узнаётся не балкой, а решёткой: два пояса с зигзагом раскосов
    /// между ними. Одна труба поперёк сцены читалась бы бельевой верёвкой.
    /// Стоит ферма ровно за установкой и не выше, чем нужно, чтобы её пояс
    /// прошёл над тарелками: поднятая ещё выше, она уходит в венец ламп и
    /// теряется в нём.
    private func lightRig(radius: Double, stand: Double,
                          project: @escaping Solid3D.Projection,
                          line: Double) -> [Solid3D.Piece]
    {
        let metal = hardware
        let post = 0.31 * radius
        let back = 0.44 * radius
        let top = -stand * 0.50
        let chord = stand * 0.055
        // Ферма гуляет. Стальная балка на двух стойках не качается на глаз,
        // но и мёртво стоять не может: она набрана из труб на болтах, стоит на
        // помосте, по которому лупит бочка, и на низах её ведёт целиком. Вся
        // сцена дышит под музыку, а ферма над ней стояла как приклеенная —
        // и именно этим выдавала, что она не конструкция, а задник.
        // Ход мелкий и медленный (0.006 роста, вдвое медленнее качки людей):
        // заметный размах превратил бы ферму в качели.
        let flex = wave(0.9, rate: 0.5) * live * stand * 0.006
        // Глубина фермы. Прежде оба пояса лежали в одной плоскости, и ферма
        // была плоской лестницей, приставленной к сцене: у настоящей балки
        // сечение квадратное, и видно её именно тем, что дальний пояс уходит
        // за ближний. Ради этого и заведено четыре пояса вместо двух.
        let girth = stand * 0.042
        let front = back - girth / 2, rear = back + girth / 2
        var pieces: [Solid3D.Piece] = []

        for side in [-1.0, 1.0] {
            let x = side * post
            pieces.append(Solid3D.contactShadow(at: (x, back), radius: stand * 0.10,
                                                strength: 0.56, project: project,
                                                drift: 0.24))
            // Плита под вышкой: труба, кончающаяся в воздухе над настилом,
            // висит, а не стоит, — а пятна касания у неё нет, слишком тонкая.
            pieces.append(Solid3D.cylinder(
                centre: (x, -stand * 0.008, back), radius: stand * 0.042,
                height: stand * 0.016, material: metal, project: project, lineWidth: line))

            // Вышка — трёхтрубная, а не одна палка. Одиночная труба под фермой
            // читается шестом: у неё нет ни толщины, ни решётки, и на кадре
            // она ничем не отличается от микрофонной стойки. Три трубы
            // с раскосами дают силуэт конструкции даже в дюжину пикселей.
            let legs: [(Double, Double)] = [(-stand * 0.026, front),
                                            (stand * 0.026, front),
                                            (0, rear + stand * 0.010)]
            for leg in legs {
                pieces.append(Solid3D.capsule(
                    from: (x + leg.0, 0, leg.1),
                    // Ведёт только макушку: пятка стоит на настиле, а гуляет
                    // верх — так гнётся всё, что защемлено внизу.
                    to: (x + leg.0 + flex, top, leg.1),
                    radius: stand * 0.0075, material: metal,
                    project: project, lineWidth: line))
            }
            // Раскосы по переднему лицу вышки: зигзаг между двумя передними
            // трубами. По нему вышка и читается решёткой, а не парой прутьев.
            let rungs = 5
            for index in 0..<rungs {
                let lower = top * Double(index) / Double(rungs)
                let upper = top * Double(index + 1) / Double(rungs)
                let leftFirst = index % 2 == 0
                pieces.append(Solid3D.capsule(
                    from: (x + (leftFirst ? -1 : 1) * stand * 0.026 + flex * lower / top,
                           lower, front),
                    to: (x + (leftFirst ? 1 : -1) * stand * 0.026 + flex * upper / top,
                         upper, front),
                    radius: stand * 0.004, material: metal,
                    project: project, lineWidth: line * 0.7))
            }
        }

        // Пояса фермы: два уровня по два пояса в глубину.
        for level in [top, top + chord] {
            for depth in [front, rear] {
                pieces.append(Solid3D.capsule(
                    from: (-post + flex, level, depth), to: (post + flex, level, depth),
                    radius: stand * 0.0075, material: metal, project: project, lineWidth: line))
            }
        }
        // Шесть пролётов вместо восьми. На экране пояса фермы разведены на
        // шесть пикселей, и раскосы в них шли частой пилой, слипавшейся в серую
        // полосу; редкий зигзаг читается решёткой, а не штриховкой.
        let bays = 6
        for index in 0..<bays {
            let a = -post + flex + 2 * post * Double(index) / Double(bays)
            let b = -post + flex + 2 * post * Double(index + 1) / Double(bays)
            pieces.append(Solid3D.capsule(
                from: (a, index % 2 == 0 ? top : top + chord, front),
                to: (b, index % 2 == 0 ? top + chord : top, front),
                radius: stand * 0.0045, material: metal, project: project, lineWidth: line * 0.7))
            // Стойка пролёта: вертикальная перемычка между поясами. Без неё
            // зигзаг висит сам по себе и балка читается лентой, а не фермой.
            pieces.append(Solid3D.capsule(
                from: (a, top, front), to: (a, top + chord, front),
                radius: stand * 0.0040, material: metal, project: project, lineWidth: line * 0.7))
        }

        // Прожекторы висят под нижним поясом и смотрят вниз-вперёд, на группу.
        // Развёрнутые строго вниз, они светили бы себе под ноги, и наклон —
        // единственное, чем видно, что свет идёт на сцену.
        //
        // Куда целит каждый прибор, задано отдельно, а не выведено из его места
        // на балке: лампы висят кучно посередине фермы, и если пустить лучи
        // отвесно, четыре пятна лягут одно на другое под самой установкой.
        // Крайние приборы разведены на фланги, к гитаристу и клавишнику,
        // средние сведены вперёд — в ту самую пустую переднюю треть, ради
        // которой всё и затевалось.
        let aims: [(Double, Double, Double)] = [(-0.56, -0.06, 0.175),
                                                (-0.16, -0.46, 0.190),
                                                (0.16, -0.46, 0.190),
                                                (0.56, -0.06, 0.175)]
        for (index, slot) in [-0.74, -0.25, 0.25, 0.74].enumerated() {
            // Прибор висит на скобе и потому качается вместе с фермой, но с
            // отставанием: подвес свободный, и груз на нём отзывается позже
            // самой балки. Отставание задано сдвигом фазы, а не отдельным
            // законом движения — иначе лампы разъедутся с фермой, на которой
            // висят.
            let swing = flex + wave(0.9 + Double(index) * 0.5 - 0.7, rate: 0.5)
                * live * stand * 0.005
            let x = post * slot + swing
            // Разгораются лампы по очереди — каждой свой сдвиг фазы в четверть
            // волны: загоревшись разом, четыре одинаковых пятна читаются не
            // светом, а мигающей гирляндой.
            let burn = max(0, wave(Double(index) * 1.57, rate: 1.4)) * live
            // Линза раскалена: у прожектора видно ровно две вещи — тёмный корпус
            // и горящее стекло, и вся его узнаваемость держится на их перепаде.
            // Линза горячая и в гамме сцены. Прежние 0.46 насыщенности вместе
            // с накладным бликом во всю её площадь давали бледное серо-голубое
            // стекло — единственное холодное пятно на всей золотой сцене.
            let lens = Solid3D.Material(saturation: 0.74,
                                        glow: 0.34 + 0.34 * burn + 0.32 * energy,
                                        opacity: 1.06)

            // Прибор собран как настоящая голова на вилке: хомут на поясе,
            // короткое основание, две щеки вилки по бокам и корпус между ними.
            // Прежде тут висел один обрубок с диском на конце — по нему не
            // читалось ни того, что прибор поворотный, ни того, что он вообще
            // прибор. Вилка стоит трёх лишних тел на лампу и окупается: именно
            // по ней голова опознаётся с одного взгляда.
            let clampY = top + chord
            let yokeY = clampY + stand * 0.030
            let headY = yokeY + stand * 0.030
            pieces.append(Solid3D.box(
                centre: (x, clampY + stand * 0.008, back),
                size: (stand * 0.030, stand * 0.016, stand * 0.030),
                material: metal, project: project, lineWidth: line))
            pieces.append(Solid3D.capsule(
                from: (x, clampY + stand * 0.014, back), to: (x, yokeY, back),
                radius: stand * 0.006, material: metal, project: project, lineWidth: line))
            for cheek in [-1.0, 1.0] {
                pieces.append(Solid3D.capsule(
                    from: (x + cheek * stand * 0.024, yokeY, back),
                    to: (x + cheek * stand * 0.024, headY + stand * 0.004, back - stand * 0.006),
                    radius: stand * 0.005, material: metal, project: project, lineWidth: line))
            }
            pieces.append(Solid3D.capsule(
                from: (x - stand * 0.024, yokeY, back),
                to: (x + stand * 0.024, yokeY, back),
                radius: stand * 0.0045, material: metal, project: project, lineWidth: line))

            // Корпус головы — цилиндр, завалённый носом вниз-вперёд. Он и есть
            // то, что вращается в вилке, поэтому линза сидит на его торце.
            let nose = (x, headY + stand * 0.026, back - stand * 0.030)
            pieces.append(Solid3D.capsule(
                from: (x, headY - stand * 0.006, back + stand * 0.006),
                to: nose,
                radius: stand * 0.019, material: metal, project: project, lineWidth: line))
            let eye = (nose.0, nose.1 + stand * 0.008, nose.2 - stand * 0.010)
            pieces.append(Solid3D.faceDisc(
                centre: eye, radius: stand * 0.019, material: lens, project: project,
                lineWidth: line, dish: 0.30, squash: 0.72))

            let aim = aims[index]
            pieces.append(spotBeam(from: eye,
                                   to: (aim.0 * radius, aim.1 * radius),
                                   pool: aim.2 * radius,
                                   burn: 0.32 + 0.42 * burn + 0.26 * energy,
                                   project: project))
        }

        return pieces
    }

    /// Луч прожектора и пятно под ним — одним телом.
    ///
    /// Ферма с приборами, которые ничего не освещают, — не свет, а карниз:
    /// прожектор опознаётся не корпусом, а тем, что от него куда-то идёт.
    /// Луч слабый и гаснет, не дойдя до пола: в воздухе виден не сам свет,
    /// а пыль в нём, и до сцены он доходит уже одним пятном. Ровно поэтому
    /// пятно рисуется отдельной заливкой, а не концом конуса.
    ///
    /// Конус и пятно собраны в один `Piece` намеренно: у сцены три сотни тел
    /// в общей сортировке, и восемь новых ради света — заметная прибавка,
    /// тогда как рисуются они всё равно подряд и одной глубиной.
    /// Глубина взята у линзы, то есть у самого дальнего конца луча: свет
    /// ложится ПОД фигуры и за них, а не поверх, — накрыв группу, конус
    /// выбелил бы её насквозь, потому что кладётся сложением.
    private func spotBeam(from lens: (Double, Double, Double),
                          to target: (Double, Double),
                          pool: Double, burn: Double,
                          project: Solid3D.Projection) -> Solid3D.Piece
    {
        let head = project(lens.0, lens.1, lens.2)
        let hit = project(target.0, 0, target.1)
        let poolRadius = max(pool * hit.1, 0.001)
        // Сплюснутость пятна берётся у проекции, как у контактной тени: круг
        // на полу эта камера показывает почти круглым, и назначенное вручную
        // блюдце сразу выдаёт себя тем, что лежит не в плоскости сцены.
        let flatten = abs(project(target.0, 0, target.1 + pool).0.y - hit.0.y) / poolRadius

        let dx = hit.0.x - head.0.x, dy = hit.0.y - head.0.y
        let run = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / run, uy = dy / run
        // Горловина луча — сама линза: конус выходит из стекла прибора, а не
        // из точки, иначе он читается верёвкой, натянутой от фермы к полу.
        let neck = poolRadius * 0.16
        var cone = Path()
        cone.move(to: CGPoint(x: head.0.x - uy * neck, y: head.0.y + ux * neck))
        cone.addLine(to: CGPoint(x: head.0.x + uy * neck, y: head.0.y - ux * neck))
        cone.addLine(to: CGPoint(x: hit.0.x + uy * poolRadius, y: hit.0.y - ux * poolRadius))
        cone.addLine(to: CGPoint(x: hit.0.x - uy * poolRadius, y: hit.0.y + ux * poolRadius))
        cone.closeSubpath()

        let disc = Path(ellipseIn: CGRect(x: hit.0.x - poolRadius,
                                          y: hit.0.y - poolRadius * flatten,
                                          width: poolRadius * 2,
                                          height: poolRadius * flatten * 2))
        let hot = Color(hue: 0.095, saturation: 0.42, brightness: 1)
        let warm = Color(hue: 0.080, saturation: 0.60, brightness: 1)

        // Глубина уведена за самое дальнее тело сцены, а не взята у линзы.
        // У луча нет одной глубины: дальним концом он висит у фермы, ближним
        // лежит на полу перед вокалистом, и любое среднее значение где-нибудь
        // да соврёт. Из двух ошибок выбрана безопасная: свет, положенный ПОД
        // всё, только подсвечивает фигуры сзади, тогда как положенный поверх
        // выбеливает их насквозь — конус кладётся сложением.
        return Solid3D.Piece(depth: head.2 + pool * 4) { context in
            context.blendMode = .plusLighter
            context.fill(
                cone,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: hot.opacity(0.078 * burn), location: 0),
                        .init(color: warm.opacity(0.036 * burn), location: 0.55),
                        .init(color: .clear, location: 1),
                    ]),
                    startPoint: head.0, endPoint: hit.0))
            context.fill(
                disc,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: hot.opacity(0.125 * burn), location: 0),
                        .init(color: warm.opacity(0.058 * burn), location: 0.44),
                        .init(color: .clear, location: 0.82),
                    ]),
                    center: hit.0, startRadius: 0, endRadius: poolRadius))
            context.blendMode = .normal
        }
    }

    // MARK: - Лучи света

    /// Лучи от столбиков громкости, падающие на сцену. Каждый идёт от макушки
    /// лампы к подиуму и гаснет к центру — так свет читается объёмным, как
    /// в дыму над сценой, а фигуры оказываются в этом свете, а не рядом с ним.
    static func beams(_ context: inout GraphicsContext,
                      from lamps: [(point: CGPoint, value: Double, nearness: Double)],
                      centre: CGPoint,
                      podiumRadius: Double,
                      palette: Palette,
                      energy: Double)
    {
        guard energy > 0.02 else { return }
        context.blendMode = .plusLighter
        let hues = palette.hues

        for lamp in lamps where lamp.value > 0.42 {
            let dx = centre.x - lamp.point.x
            let dy = centre.y - lamp.point.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 1 else { continue }
            let ux = dx / length, uy = dy / length
            // Луч сужается к центру: у источника он шире, чем в точке падения.
            let spread = podiumRadius * 0.055 * (0.5 + lamp.value)

            var wedge = Path()
            wedge.move(to: CGPoint(x: lamp.point.x - uy * spread, y: lamp.point.y + ux * spread))
            wedge.addLine(to: CGPoint(x: lamp.point.x + uy * spread, y: lamp.point.y - ux * spread))
            wedge.addLine(to: CGPoint(x: centre.x + uy * spread * 0.18, y: centre.y - ux * spread * 0.18))
            wedge.addLine(to: CGPoint(x: centre.x - uy * spread * 0.18, y: centre.y + ux * spread * 0.18))
            wedge.closeSubpath()

            let alpha = (lamp.value - 0.42) / 0.58 * 0.16 * (0.4 + 0.6 * energy) * lamp.nearness
            context.fill(wedge,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: Color(hue: hues.hot, saturation: palette.saturation * 0.45,
                                                    brightness: 1).opacity(alpha), location: 0.0),
                                 .init(color: Color(hue: hues.hot, saturation: palette.saturation * 0.55,
                                                    brightness: 1).opacity(alpha * 0.25), location: 0.55),
                                 .init(color: .clear, location: 1.0),
                             ]),
                             startPoint: lamp.point, endPoint: centre))
        }
        context.blendMode = .normal
    }
}
