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
        drawPodium(&context, project: project, radius: radius, base: base)

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
                          project: project, line: line)
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
                          project: project, line: line)
        pieces += speaker(at: place( 0.545, 0.17), height: stand * 0.385, turn: 0.34,
                          project: project, line: line)
        pieces += guitarist(at: place(-0.30, -0.09), height: stand * 0.44,
                            project: project, line: line)
        pieces += keyboardist(at: place(0.30, -0.07), height: stand * 0.42,
                              project: project, line: line)
        // Рост вокалиста считан по экрану, а не назначен на глаз. Камера с
        // перспективой: вынесенный к зрителю на 0.37 радиуса певец и так
        // получает прибавку в масштабе, и прежние 0.50 роста давали на кадре
        // фигуру на семнадцать процентов выше гитариста — среди своих он
        // выглядел не фронтменом, а взрослым в компании подростков.
        // Оставшийся запас в пару процентов — намеренный: фронтмен впереди
        // группы и должен быть чуть крупнее, но именно чуть.
        pieces += vocalist(at: place(0.00, -0.37), height: stand * 0.437,
                           project: project, line: line)

        // Ферма позади группы: единственное, что стоит выше людей, — поэтому
        // она и читается сценой, а не помостом с фигурами.
        pieces += lightRig(radius: radius, stand: stand, project: project, line: line)

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
                           project: project, line: line)
        pieces += micStand(base: place(0.402, -0.168), height: stand * 0.44,
                           boom: (-stand * 0.070, -stand * 0.098, radius * 0.045),
                           project: project, line: line)

        // Мониторы у края подиума, вдоль передней дуги. Дальше выносить нельзя:
        // край подиума на 0.72 радиуса, а вправо и влево от середины передняя
        // дуга уходит под самый венец, и клин ложится на светящиеся столбики.
        // Клинья разнесены по дуге, по одному на музыканта: сдвинутые к середине,
        // все три встают в кучу под вокалистом, а перед гитаристом и клавишником
        // остаётся пустой пол.
        pieces += monitor(at: place(-0.395, -0.475), width: stand * 0.115, turn: -0.62,
                          project: project, line: line)
        // Средний клин довёрнут чуть вбок: поставленный анфас, он показывает
        // камере одну грань и читается плоской карточкой — тем же, чем читались
        // неразвёрнутые колонки портала.
        pieces += monitor(at: place(0.000, -0.535), width: stand * 0.125, turn: 0.26,
                          project: project, line: line)
        pieces += monitor(at: place(0.395, -0.460), width: stand * 0.115, turn: 0.64,
                          project: project, line: line)

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
                        project: project, line: line)
        pieces += cable(from: (place(0.362, -0.125).0, -stand * 0.185, place(0.362, -0.125).1),
                        to: (place(0.500, 0.095).0, 0, place(0.500, 0.095).1),
                        bow: -radius * 0.026, hang: stand * 0.070, gauge: gauge,
                        project: project, line: line)
        // Провод вокалиста уходит от микрофона к переднему монитору: ручной
        // микрофон без шнура читается не микрофоном, а гантелью. Конец провода
        // посажен на предмет, а не в пустоту — оборванный посреди сцены шнур
        // выглядит не проводкой, а хвостом.
        // Уведён вбок от фигуры и выгнут вчетверо сильнее прежнего: трасса тут
        // короткая, а падение — во весь рост, и прямая от руки к полу читалась
        // не шнуром, а шестом, приставленным к певцу. Провод узнаётся кривизной,
        // и кривизну ему приходится задавать поперёк, там где её видно.
        pieces += cable(from: (place(0.038, -0.380).0, -stand * 0.398, place(0.038, -0.380).1),
                        to: (place(0.088, -0.520).0, 0, place(0.088, -0.520).1),
                        bow: -radius * 0.085, hang: stand * 0.105, gauge: gauge,
                        project: project, line: line)

        // Общая сортировка: без неё тела накладываются в порядке создания
        // и объём рассыпается.
        pieces.sort { $0.depth > $1.depth }
        for piece in pieces {
            piece.render(&context)
        }
    }

    // MARK: - Подиум

    private func drawPodium(_ context: inout GraphicsContext,
                            project: Solid3D.Projection,
                            radius: Double,
                            base: Double)
    {
        let podiumRadius = radius * 0.72
        var disc = Path()
        for step in 0...120 {
            let theta = Double(step) / 120 * 2 * .pi
            let point = project(cos(theta) * podiumRadius, 0, sin(theta) * podiumRadius).0
            if step == 0 { disc.move(to: point) } else { disc.addLine(to: point) }
        }
        disc.closeSubpath()

        let bounds = disc.boundingRect
        context.fill(disc,
                     with: .linearGradient(
                         Gradient(colors: [
                             Color(hue: 0.085, saturation: 0.55, brightness: 1)
                                 .opacity(0.020 + 0.026 * energy),
                             Color(hue: 0.055, saturation: 0.8, brightness: 1).opacity(0.005),
                         ]),
                         startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                         endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))

        context.blendMode = .plusLighter
        context.stroke(disc,
                       with: .color(Color(hue: 0.095, saturation: 0.45, brightness: 1)
                           .opacity(0.16 + 0.22 * energy)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0010)))
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
            let wide = pose.stance
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
            let heel = seated ? figure.at(side * 0.078 * wide, 0.044, -0.236)
                              : figure.at(side * 0.040 * wide, 0.034, 0.014 - step)
            let toe = seated ? figure.at(side * (0.078 * wide + 0.034), 0.026, -0.340)
                             : figure.at(side * (0.040 * wide + 0.032), 0.024, -0.090 - step)

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
                radius: figure.size(0.023),
                material: material, project: project, lineWidth: line))
            // Пятка шаром: без неё стопа сзади срезана и голень упирается
            // в пол торцом капсулы.
            pieces.append(Solid3D.sphere(
                centre: heel, radius: figure.size(0.024),
                material: material, project: project, lineWidth: line))
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
        // предмета за спиной, на котором читался бы его силуэт, у него нет:
        // вся его читаемость держится на собственном перепаде с полом.
        let glow = 0.48 + 0.52 * energy
        let density = 0.64
        var pieces = body(figure, glow: glow, density: density, project: project, line: line)

        // Рука вскинута вверх и назад; на ударе поднимается ещё выше, а между
        // ударами качается вместе с корпусом — застывшая рука над качающимся
        // телом выглядит подвешенной на нитке.
        let lift = 0.03 + 0.06 * beat + 0.020 * sway
        pieces += arm(figure,
                      shoulder: figure.held(-0.078, 0.788),
                      elbow: figure.held(-0.175, 0.902, 0.020),
                      wrist: figure.held(-0.210, 1.047 + lift, 0.030),
                      glow: glow, density: density, project: project, line: line)

        // Вторая рука подносит микрофон к лицу: локоть отведён вниз и в
        // сторону, предплечье идёт вверх поперёк груди. Сложенная вдвое
        // рука сливалась в один клин без сустава.
        pieces += arm(figure,
                      shoulder: figure.held(0.078, 0.788),
                      elbow: figure.held(0.175, 0.685, -0.050),
                      wrist: figure.held(0.090, 0.824, -0.070),
                      glow: glow, density: density, project: project, line: line)

        pieces.append(Solid3D.capsule(
            from: figure.held(0.070, 0.834, -0.050),
            to: figure.held(0.015, 0.898, -0.020),
            radius: figure.size(0.013),
            material: Solid3D.Material(saturation: 0.10, glow: 0.6 + 0.4 * energy, opacity: 0.60),
            project: project, lineWidth: line))

        return pieces
    }

    private func guitarist(at foot: (Double, Double), height h: Double,
                           project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        // Поза гитариста: наклон вперёд над декой, ноги широко расставлены и
        // левая отставлена назад в упор, плечи развёрнуты к грифу — правое
        // ушло назад, левое вышло к зрителю, поэтому гриф сам поднимается
        // в кадре: разворот несёт с собой и гитару.
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
                                        stance: 1.75, stride: -0.055,
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
        let lift = 0.30, reach = 0.954
        func gtr(_ along: Double, _ across: Double = 0, _ out: Double = 0)
            -> (Double, Double, Double)
        {
            figure.held(-0.120 + along * reach - across * lift,
                        0.560 + along * lift + across * reach,
                        // Гриф уходит к зрителю: гитара развёрнута, а не
                        // приклеена к животу плашмя.
                        -0.085 + out - along * 0.055)
        }

        // Обе кисти заданы в осях самой гитары, а не в осях фигуры: тогда любой
        // доворот инструмента уносит руки с собой и они не отрываются от струн.
        // Локти поставлены по длине костей — плечо около 0.19 роста, предплечье
        // около 0.16. Правая ходит поперёк струн у бриджа, левая ползёт вдоль
        // грифа: это единственное, чем видна смена аккордов.
        pieces += arm(figure,
                      shoulder: figure.held(-0.078, 0.788),
                      elbow: figure.held(-0.205, 0.640 + 0.012 * strum, -0.040),
                      wrist: gtr(0.010, -0.010 + 0.052 * strum, -0.062),
                      glow: glow, density: 0.56, project: project, line: line)
        // Левая рука пересекает гриф, а не лежит вдоль него: локоть висит выше
        // линии грифа, кисть уходит под него. Предплечье, уложенное вдоль,
        // сливалось с грифом в одну толстую конусную палку, и от гитары
        // оставалась пара дисков с рукой. Хват взят ближе к деке — тогда
        // весь верх грифа с головкой остаётся открытым.
        pieces += arm(figure,
                      shoulder: figure.held(0.078, 0.788),
                      elbow: figure.held(0.110, 0.608, -0.005),
                      wrist: gtr(0.360 + 0.038 * fret, -0.040, 0.010),
                      glow: glow, density: 0.56, project: project, line: line)

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
            centre: gtr(0), radius: figure.size(0.114),
            material: wood, project: project, lineWidth: line, dish: 0.34))
        pieces.append(Solid3D.faceDisc(
            centre: gtr(0.150), radius: figure.size(0.085),
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
        // Поза клавишника: корпус подан к инструменту, ноги под собой почти
        // сомкнуты — он не стоит враспор, а держится за клавиши. Наклон
        // небольшой: глубокий над клавишами читается уже как поклон.
        //
        // Движение: корпус чуть ведёт над клавишами, а кисти бегают по ним
        // каждая своим темпом. Одинаковый ход обеих кистей читался бы игрой
        // на гармошке, поэтому темпы взяты несоизмеримые — руки расходятся
        // и сходятся не повторяясь.
        let sway = wave(4.2, rate: 0.9) * live
        let leftRun = wave(0.0, rate: 1.9) * live
        let rightRun = wave(2.6, rate: 2.7) * live
        // Нажатие: на ударе кисти оседают на клавиши. Ход маленький, но именно
        // он отличает игру от рук, положенных на инструмент.
        let press = 0.014 * beat
        let figure = Anatomy(foot: foot, height: h * (1 - 0.010 * beat),
                             pose: Pose(lean: 0.090 + 0.022 * sway, twist: 0.10,
                                        roll: 0.026 * sway, stance: 0.90,
                                        stride: 0.035,
                                        headTilt: -0.038 - 0.014 * beat + 0.012 * sway),
                             project: project)
        let glow = 0.36 + 0.50 * energy
        var pieces = body(figure, glow: glow, density: 0.56, project: project, line: line)

        // Руки разные: левая ушла в нижний край клавиатуры, правая играет
        // ближе к середине. Симметричные руки читались как стойка «смирно»
        // над инструментом — играют именно врозь.
        // Локти прижаты к бокам. Разведённые, они уходили за края клавиатуры,
        // и предплечья падали отвесно по обе стороны от неё: инструмент
        // оказывался не под руками, а в рамке из них, а сам клавишник —
        // торсом, поставленным за столик.
        pieces += arm(figure,
                      shoulder: figure.held(-0.078, 0.788),
                      elbow: figure.held(-0.126, 0.640, -0.030),
                      wrist: figure.held(-0.132 + 0.034 * leftRun, 0.531 - press, -0.144),
                      glow: glow, density: 0.56, project: project, line: line)
        pieces += arm(figure,
                      shoulder: figure.held(0.078, 0.788),
                      elbow: figure.held(0.112, 0.645, -0.038),
                      wrist: figure.held(0.062 + 0.040 * rightRun, 0.553 - press, -0.152),
                      glow: glow, density: 0.56, project: project, line: line)

        pieces += keyRig(figure, tall: h, project: project, line: line)

        return pieces
    }

    /// Инструмент клавишника: корпус с боковинами, ряд клавиш поверх и стойка
    /// крестовиной. Прежде тут лежала одна плита — по ней не видно ни клавиш,
    /// ни того, что она на чём-то стоит, и клавишник упирался руками в полку.
    ///
    /// Разметка идёт через `at` на уровнях ниже таза, где поза даёт нулевой
    /// наклон: инструмент стоит на полу и качаться вместе с человеком за ним
    /// не должен.
    ///
    /// Высота полки взята не по уровню, а по экрану. Камера смотрит сверху,
    /// и вынос инструмента на 0.20 роста к зрителю опускает его в кадре ещё
    /// почти на 0.10 роста: клавиатура, заданная по поясу, оказывалась у колен,
    /// а кисти висели над ней в воздухе. Верх клавиш поднят до 0.480 роста —
    /// на экране это как раз под кулаками.
    private func keyRig(_ figure: Anatomy, tall h: Double,
                        project: @escaping Solid3D.Projection,
                        line: Double) -> [Solid3D.Piece]
    {
        // Корпус того же густого золота, что бэклайн: прежняя серая плита
        // выпадала из гаммы и читалась куском пенопласта на палках.
        let shell = Solid3D.Material(saturation: 0.90, glow: 0.16 + 0.30 * air, opacity: 1.28)
        let cheek = Solid3D.Material(saturation: 0.84, glow: 0.24 + 0.34 * air, opacity: 1.28)
        // Клавиши светлее корпуса, но остаются золотом — белым на этой сцене
        // бывает только блик. Накал у них сдержанный сознательно: разогнанный
        // ряд оказывался самым ярким пятном сцены и съедал лежащие на нём
        // кисти — стеклянная рука на раскалённой клавише просто пропадала.
        // Чёрные наоборот загнаны в самый насыщенный тон при нулевом накале:
        // различает ряды именно этот перепад, потому что по размеру на этой
        // камере клавиша — три пикселя.
        let ivory = Solid3D.Material(saturation: 0.68, glow: 0.26 + 0.28 * air, opacity: 1.20)
        let ebony = Solid3D.Material(saturation: 0.98, glow: 0.03, opacity: 1.45)
        let rack = Solid3D.Material(saturation: 0.72, glow: 0.10 + 0.20 * air, opacity: 0.55)
        var pieces: [Solid3D.Piece] = []

        pieces.append(Solid3D.contactShadow(at: (figure.x, figure.z - figure.size(0.205)),
                                            radius: figure.size(0.28),
                                            strength: 0.44, project: project,
                                            drift: 0.30))

        // Стойка крестовиной: две трубы, перекрещенные под корпусом, с опорами
        // на полу и полками под днищем. Две вертикальные палки, стоявшие тут
        // раньше, читались ходулями — стойка узнаётся именно крестом.
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.capsule(
                from: figure.at(side * 0.216, 0, -0.150),
                to: figure.at(-side * 0.216, 0.408, -0.252),
                radius: figure.size(0.011), material: rack,
                project: project, lineWidth: line))
            pieces.append(Solid3D.capsule(
                from: figure.at(side * 0.216, 0, -0.096),
                to: figure.at(side * 0.216, 0, -0.204),
                radius: figure.size(0.010), material: rack,
                project: project, lineWidth: line))
            pieces.append(Solid3D.capsule(
                from: figure.at(side * 0.216, 0.408, -0.198),
                to: figure.at(side * 0.216, 0.408, -0.288),
                radius: figure.size(0.010), material: rack,
                project: project, lineWidth: line))
        }

        // Корпус и боковины. Боковины выше клавиш и выступают за них по глубине:
        // это те самые щёки, между которыми и сидит ряд, — без них клавиши
        // висят на плите открытым краем.
        pieces.append(Solid3D.box(
            centre: figure.at(0, 0.430, -0.205),
            size: (figure.size(0.460), h * 0.046, figure.size(0.150)),
            material: shell, project: project, lineWidth: line))
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.box(
                centre: figure.at(side * 0.243, 0.438, -0.208),
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
                centre: figure.at(-0.220 + pitch * (Double(index) + 0.5), 0.4605, -0.237),
                size: (figure.size(pitch * 0.94), h * 0.015, figure.size(0.094)),
                // Обводка у клавиш тоньше общей: при полной она съедала саму
                // клавишу в три пикселя, и ряд читался штакетником.
                material: ivory, project: project, lineWidth: line * 0.7))
        }
        for index in [0, 1, 3, 4, 5, 7] {
            pieces.append(Solid3D.box(
                centre: figure.at(-0.220 + pitch * Double(index + 1), 0.4635, -0.215),
                size: (figure.size(0.024), h * 0.022, figure.size(0.050)),
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
                             pose: Pose(lean: 0.130 + 0.030 * beat,
                                        twist: 0.06 + 0.050 * stroke * live, stance: 1.70,
                                        hip: 0.290, headTilt: -0.030 - 0.045 * beat),
                             project: project)
        var pieces = body(figure, glow: glow, density: 0.56, project: project, line: line)

        // Кисти опущены к пластикам, а локти висят у боков. Уровень рук задан
        // не на глаз, а от барабанов: запястье приходит примерно на высоту
        // обода малого, иначе палочки машут в пустоте над установкой. Поднятый
        // локоть на этой камере уходит выше головы, и фигура читается не
        // барабанщиком, а насекомым. Запястье ходит вслед за замахом своей
        // руки: палочка, поднятая при неподвижной кисти, отрывается от руки.
        for side in [-1.0, 1.0] {
            pieces += arm(figure,
                          shoulder: figure.held(side * 0.078, figure.shoulder),
                          elbow: figure.held(side * 0.140, 0.452, 0.020),
                          wrist: figure.held(side * 0.238, 0.436 + 0.055 * hand(side), -0.070),
                          glow: glow, density: 0.56, project: project, line: line)
        }

        pieces += drumKit(figure, tall: tall, project: project, line: line)

        // Палочки продолжают предплечья и смотрят вниз, на пластики: поднятые
        // концами вверх, они читались усами, а не замахом. Замах у каждой
        // палочки свой — тот же попеременный ход, что и у кистей, — а удар
        // добавляет обеим общий подъём, потому что на сильную долю бьют разом.
        for side in [-1.0, 1.0] {
            let raise = 0.015 + 0.130 * hand(side) + 0.030 * beat
            pieces.append(Solid3D.capsule(
                // Хват поднимается сильнее запястья: кулак вынесен за него по
                // оси предплечья, и подъём кисти доезжает до него с рычагом.
                from: figure.held(side * 0.278, 0.452 + 0.072 * hand(side), -0.098),
                to: figure.held(side * 0.312, 0.368 + raise, -0.234),
                radius: figure.size(0.017),
                material: Solid3D.Material(saturation: 0.34, glow: 0.5 + 0.5 * beat, opacity: 0.72),
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
        let head = Solid3D.Material(saturation: 0.70, glow: 0.28 + 0.40 * bass, opacity: 1.20)
        // Железо стоек глушится непрозрачностью, а не тоном: у этого материала
        // яркость задаётся освещённостью, и притемнить трубку иначе нечем.
        // А глушить надо: тонких трубок в установке два десятка, и вместе они
        // дают больше света, чем все корпуса разом, — получался не бэклайн,
        // а моток проволоки, в котором где-то спрятаны барабаны.
        let metal = Solid3D.Material(saturation: 0.72, glow: 0.10 + 0.20 * air, opacity: 0.50)
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
                           0.008)
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
        pieces.append(Solid3D.contactShadow(at: (x, z - 0.28 * unit), radius: unit * 0.66,
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
            centre: kit(0, 0.236, 0.008), radius: unit * 0.106, height: tall * 0.030,
            material: metal, project: project, lineWidth: line))
        pieces.append(rod((0, 0, 0.014), (0, 0.226, 0.014), 0.018))
        // Ноги стула разведены шире обычной треноги и развёрнуты одна назад,
        // две вперёд-вбок. Узкая тренога под стулом целиком тонет за бочкой:
        // на экране всё, что ниже её верхней кромки и уже её поперечника,
        // просто закрыто. Разведённые ноги выходят за край бочки — и стул
        // виден, а вместе с ним видно, что барабанщик сидит.
        for index in 0..<3 {
            let angle = Double(index) * 2.094
            pieces.append(rod((sin(angle) * 0.028, 0.120, 0.014 + cos(angle) * 0.028),
                              (sin(angle) * 0.215, 0, 0.014 + cos(angle) * 0.215),
                              0.009))
        }

        // Бочка лежит на боку, поэтому это капсула вдоль глубины, а не
        // вертикальный цилиндр: вертикальный давал барабан, поставленный
        // стоймя, и передняя мембрана висела на нём отдельным кругом.
        pieces.append(Solid3D.contactShadow(at: (x, z - 0.55 * unit), radius: unit * 0.24,
                                            strength: 0.52, project: project))
        pieces.append(Solid3D.capsule(
            from: kit(0, 0.170, -0.430), to: kit(0, 0.170, -0.650),
            radius: unit * 0.160, material: shell, project: project, lineWidth: line))
        pieces.append(Solid3D.faceDisc(
            centre: kit(0, 0.170, -0.656), radius: unit * 0.154,
            material: head, project: project, lineWidth: line, dish: 0.25))
        // Лапы: бочка без них не стоит, а лежит боком и норовит укатиться.
        // Пара упоров вперёд-вниз — то единственное, чем она держится.
        for side in [-1.0, 1.0] {
            pieces.append(rod((side * 0.145, 0.190, -0.520), (side * 0.258, 0, -0.635), 0.012))
        }
        // Педаль. Она вынесена к правому краю обода, а не в его середину:
        // по центру её целиком закрывает сам корпус бочки, и от педали
        // остаётся ровно ничего. У края видны и рама на полу, и колотушка.
        pieces.append(Solid3D.box(
            centre: kit(0.176, 0.017, -0.398),
            size: (unit * 0.072, tall * 0.030, unit * 0.120),
            material: metal, project: project, lineWidth: line))
        pieces.append(rod((0.176, 0.024, -0.448), (0.176, 0.178, -0.442), 0.010))
        pieces.append(Solid3D.sphere(
            centre: kit(0.176, 0.196, -0.440), radius: unit * 0.024,
            material: metal, project: project, lineWidth: line))

        // Томы висят на кронштейне из верха бочки — так их и держат на самом
        // деле. Отдельные стойки до пола пришлось бы вести сквозь корпус бочки.
        // Уровень томов подобран так, чтобы их днища приходились ровно на
        // верхнюю кромку бочки: посаженные ниже, они тонут в её силуэте, и
        // весь центр установки превращается в одно золотое пятно.
        pieces.append(rod((0, 0.322, -0.520), (0, 0.482, -0.520), 0.012))
        for side in [-1.0, 1.0] {
            pieces.append(rod((0, 0.482, -0.520), (side * 0.104, 0.488, -0.520), 0.010))
            pieces.append(drum(side * 0.128, 0.478, -0.520, radius: 0.086, depthHeight: 0.150))
        }

        // Напольный том: три ноги от середины корпуса к полу, как у него и есть.
        pieces.append(Solid3D.contactShadow(at: (x + 0.318 * unit, z - 0.290 * unit),
                                            radius: unit * 0.17, strength: 0.40, project: project))
        for index in 0..<3 {
            let angle = Double(index) * 2.094 + 0.9
            pieces.append(rod((0.318 + sin(angle) * 0.104, 0.250, -0.290 + cos(angle) * 0.104),
                              (0.318 + sin(angle) * 0.146, 0, -0.290 + cos(angle) * 0.146),
                              0.011))
        }
        pieces.append(drum(0.318, 0.232, -0.290, radius: 0.112, depthHeight: 0.226))

        // Малый на треноге: колонка идёт от пола к корзине под самым корпусом.
        pieces += tripod(-0.290, -0.180, hub: 0.115, reach: 0.100)
        pieces.append(rod((-0.290, 0, -0.180), (-0.290, 0.262, -0.180), 0.013))
        pieces.append(drum(-0.290, 0.302, -0.180, radius: 0.100, depthHeight: 0.078))

        // Хай-хэт: две тарелки на одной стойке. Верхняя разводится с нижней
        // между ударами и захлопывается на доле — это единственное движение,
        // по которому пара тарелок читается хай-хэтом, а не сдвоенным крашем.
        let hats = 0.030 * (1 - beat) * live
        pieces += tripod(-0.430, -0.330, hub: 0.120, reach: 0.104)
        pieces.append(Solid3D.box(
            centre: kit(-0.430, 0.016, -0.262),
            size: (unit * 0.066, tall * 0.028, unit * 0.108),
            material: metal, project: project, lineWidth: line))
        pieces.append(rod((-0.430, 0, -0.330), (-0.430, 0.500, -0.330), 0.013))
        pieces.append(cymbal(-0.430, 0.486, -0.330, 0.092))
        pieces.append(rod((-0.430, 0.488, -0.330), (-0.430, 0.606 + hats, -0.330), 0.008))
        pieces.append(cymbal(-0.430, 0.556 + hats, -0.330, 0.096))

        // Райд справа и краш слева-сверху. Стойки наклонные: у прямой вертикали
        // тарелка сидит ровно на треноге и вся конструкция читается грибом.
        pieces += tripod(0.520, -0.330, hub: 0.130, reach: 0.112)
        pieces.append(rod((0.520, 0, -0.330), (0.455, 0.532, -0.428), 0.013))
        pieces.append(cymbal(0.455, 0.545, -0.430, 0.140))

        pieces += tripod(-0.680, -0.400, hub: 0.135, reach: 0.112)
        pieces.append(rod((-0.680, 0, -0.400), (-0.640, 0.726, -0.466), 0.012))
        pieces.append(cymbal(-0.640, 0.740, -0.470, 0.115))

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

        // Тень уведена из-под стека: сверху ящик накрывает своё основание
        // целиком, и посаженная по центру она пропадала под ним без остатка —
        // портал висел в воздухе, хотя стоял на полу всеми четырьмя углами.
        pieces.append(Solid3D.contactShadow(at: (x, z), radius: h * 0.30,
                                            strength: 0.78, project: project,
                                            drift: 0.62))

        // Подставка: кабинет на площадке никогда не стоит прямо на полу, под
        // ним брус или колёса. Без неё стек выглядит вкопанным в сцену.
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.025, 0),
            size: (h * 0.44, h * 0.05, h * 0.38),
            material: cabinet, project: project, lineWidth: line, yaw: turn))

        // Сабвуфер: широкий и глубокий, от 0.05h до 0.50h.
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.275, 0),
            size: (h * 0.42, h * 0.45, h * 0.34),
            material: cabinet, project: project, lineWidth: line, yaw: turn))

        // Топ: уже саба и отодвинут вглубь, так что фасады не в одной плоскости.
        // Этот уступ и есть то, по чему стопка читается двумя кабинетами, а не
        // одним высоким ящиком: у сплошного корпуса излома фасада не бывает.
        let inset = h * 0.03
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.71, inset),
            size: (h * 0.34, h * 0.42, h * 0.28),
            material: cabinet, project: project, lineWidth: line, yaw: turn))

        // Динамики — диски на фасаде, а не шары, выпирающие из корпуса.
        pieces.append(Solid3D.faceDisc(
            centre: local(0, -h * 0.30, -h * 0.172), radius: h * 0.135,
            material: cone, project: project, lineWidth: line))
        pieces.append(Solid3D.faceDisc(
            centre: local(0, -h * 0.62, inset - h * 0.142), radius: h * 0.078,
            material: cone, project: project, lineWidth: line))

        // Щель фазоинвертора внизу саба и рупор над серединой топа — мелочи,
        // по которым ящик читается акустикой, а не тумбой.
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.100, -h * 0.166),
            size: (h * 0.24, h * 0.040, h * 0.028),
            material: slot, project: project, lineWidth: line, yaw: turn))
        pieces.append(Solid3D.box(
            centre: local(0, -h * 0.805, inset - h * 0.136),
            size: (h * 0.22, h * 0.085, h * 0.028),
            material: slot, project: project, lineWidth: line, yaw: turn))

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
        Solid3D.Material(saturation: 0.72, glow: 0.10 + 0.20 * air, opacity: 0.50)
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
    private func micStand(base: (Double, Double), height h: Double,
                          boom: (Double, Double, Double),
                          project: @escaping Solid3D.Projection,
                          line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = base
        let metal = hardware
        // Микрофон светлее железа: это единственная деталь стойки, которую
        // на таком размере видно как предмет, а не как линию. Но разогнать его
        // ярче нельзя — стойка тонкая и тусклая, и раскалённая головка на её
        // конце отрывается от неё, повисая в воздухе отдельной блёсткой.
        let capsuleHead = Solid3D.Material(saturation: 0.78, glow: 0.24 + 0.30 * energy,
                                           opacity: 0.80)
        var pieces: [Solid3D.Piece] = []

        pieces.append(Solid3D.contactShadow(at: (x, z), radius: h * 0.16,
                                            strength: 0.38, project: project))

        // Тренога. Ноги обязательно кончаются на нуле: труба, оборванная выше
        // пола, сразу выдаёт, что предмет не поставлен, а нарисован.
        for index in 0..<3 {
            let angle = Double(index) * 2.094 + 0.5
            pieces.append(Solid3D.capsule(
                from: (x + sin(angle) * h * 0.016, -h * 0.070, z + cos(angle) * h * 0.016),
                to: (x + sin(angle) * h * 0.105, 0, z + cos(angle) * h * 0.105),
                radius: h * 0.008, material: metal, project: project, lineWidth: line))
        }

        let neck = (x, -h * 0.74, z)
        pieces.append(Solid3D.capsule(
            from: (x, -h * 0.055, z), to: neck,
            radius: h * 0.018, material: metal, project: project, lineWidth: line))
        // Барашек на изломе: без него журавль прирастает к колонне торцом
        // и стойка ломается пополам ровно там, где у настоящей сустав.
        pieces.append(Solid3D.sphere(
            centre: neck, radius: h * 0.026,
            material: metal, project: project, lineWidth: line))

        let head = (neck.0 + boom.0, neck.1 + boom.1, neck.2 + boom.2)
        pieces.append(Solid3D.capsule(
            from: neck, to: head,
            radius: h * 0.016, material: metal, project: project, lineWidth: line))
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
    private func monitor(at foot: (Double, Double), width w: Double, turn: Double,
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
        let tilt = 0.46
        pieces.append(Solid3D.box(
            centre: local(0, -w * 0.035, -w * 0.020),
            size: (w * 0.90, w * 0.07, w * 0.50),
            material: cabinet, project: project, lineWidth: line, yaw: turn))
        pieces.append(Solid3D.box(
            centre: local(0, -w * 0.215, w * 0.045),
            size: (w * 0.94, w * 0.30, w * 0.58),
            material: cabinet, project: project, lineWidth: line, yaw: turn, pitch: tilt))

        // Динамик утоплен в скошенную панель. Нормаль панели — местная вертикаль,
        // заваленная тем же углом, поэтому диск сам уезжает вслед за наклоном
        // корпуса и не остаётся лежать плашмя на его крыше. Диск взят во всю
        // панель: на предмете в тридцать пикселей у монитора остаётся ровно
        // один опознавательный знак, и мельчить его нельзя.
        let lift = w * 0.160
        pieces.append(Solid3D.faceDisc(
            centre: local(0, -w * 0.215 - lift * cos(tilt), w * 0.045 + lift * sin(tilt)),
            radius: w * 0.335, material: cone, project: project,
            lineWidth: line, dish: 0.42, squash: 0.58))

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
        // Семь звеньев, а не девять: на этой длине дуга и так гладкая, а каждое
        // звено — отдельное тело в общей сортировке, и три провода стоили сцене
        // почти десятой доли всех её тел.
        let steps = 7
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
        var pieces: [Solid3D.Piece] = []

        for side in [-1.0, 1.0] {
            let x = side * post
            pieces.append(Solid3D.contactShadow(at: (x, back), radius: stand * 0.10,
                                                strength: 0.40, project: project))
            for index in 0..<3 {
                let angle = Double(index) * 2.094 + 0.4
                pieces.append(Solid3D.capsule(
                    from: (x + sin(angle) * stand * 0.018, -stand * 0.080,
                           back + cos(angle) * stand * 0.018),
                    to: (x + sin(angle) * stand * 0.090, 0, back + cos(angle) * stand * 0.090),
                    radius: stand * 0.007, material: metal, project: project, lineWidth: line))
            }
            pieces.append(Solid3D.capsule(
                from: (x, -stand * 0.06, back), to: (x, top, back),
                radius: stand * 0.011, material: metal, project: project, lineWidth: line))
        }

        // Пояса фермы и раскосы между ними.
        for level in [top, top + chord] {
            pieces.append(Solid3D.capsule(
                from: (-post, level, back), to: (post, level, back),
                radius: stand * 0.008, material: metal, project: project, lineWidth: line))
        }
        let bays = 8
        for index in 0..<bays {
            let a = -post + 2 * post * Double(index) / Double(bays)
            let b = -post + 2 * post * Double(index + 1) / Double(bays)
            pieces.append(Solid3D.capsule(
                from: (a, index % 2 == 0 ? top : top + chord, back),
                to: (b, index % 2 == 0 ? top + chord : top, back),
                radius: stand * 0.005, material: metal, project: project, lineWidth: line * 0.7))
        }

        // Прожекторы висят под нижним поясом и смотрят вниз-вперёд, на группу.
        // Развёрнутые строго вниз, они светили бы себе под ноги, и наклон —
        // единственное, чем видно, что свет идёт на сцену.
        for (index, slot) in [-0.74, -0.25, 0.25, 0.74].enumerated() {
            let x = post * slot
            let hang = (x, top + chord + stand * 0.022, back)
            let nose = (x, top + chord + stand * 0.062, back - stand * 0.030)
            // Линза раскалена: у прожектора видно ровно две вещи — тёмный корпус
            // и горящее стекло, и вся его узнаваемость держится на их перепаде.
            // Разгораются лампы по очереди — каждой свой сдвиг фазы в четверть
            // волны: загоревшись разом, четыре одинаковых пятна читаются не
            // светом, а мигающей гирляндой.
            let burn = max(0, wave(Double(index) * 1.57, rate: 1.4)) * live
            let lens = Solid3D.Material(saturation: 0.46,
                                        glow: 0.34 + 0.34 * burn + 0.32 * energy,
                                        opacity: 0.92)
            pieces.append(Solid3D.capsule(
                from: (x, top + chord, back), to: hang,
                radius: stand * 0.005, material: metal, project: project, lineWidth: line))
            pieces.append(Solid3D.capsule(
                from: hang, to: nose,
                radius: stand * 0.017, material: metal, project: project, lineWidth: line))
            pieces.append(Solid3D.faceDisc(
                centre: (nose.0, nose.1 + stand * 0.006, nose.2 - stand * 0.008),
                radius: stand * 0.017, material: lens, project: project,
                lineWidth: line, dish: 0.30, squash: 0.72))
        }

        return pieces
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
