# FM Radio для iOS

Нативний SwiftUI-застосунок на основі веб-плеєра з `index.html`. Ті самі станції, групи й метадані (виконавець — пісня), iOS 16+.

## Збірка (потрібен Mac з Xcode 15+)

```sh
brew install xcodegen
cd ios
xcodegen generate
open FMRadio.xcodeproj
```

У Xcode вкажіть свою команду в Signing & Capabilities і змініть `PRODUCT_BUNDLE_IDENTIFIER` у `project.yml` (зараз `com.example.fmradio`). Запускайте на реальному пристрої: у Simulator не видно системного повзунка гучності.

Без XcodeGen: створіть новий iOS App проєкт (SwiftUI), перетягніть у нього `*.swift` та `Assets.xcassets`, а у Signing & Capabilities додайте Background Modes → Audio, AirPlay, and Picture in Picture.

## Відмінності від веб-версії

- Фонове відтворення, керування з екрана блокування і Control Center (Now Playing, play/pause).
- Автопауза під час дзвінка й відновлення після нього.
- Гучність: застосунок не може змінювати її програмно, тому замість свого повзунка стоїть системний `MPVolumeView`, який керує гучністю пристрою. Окремої кнопки mute немає, є апаратні кнопки.
- Після паузи потік відкривається заново, тож звучить прямий ефір, а не старий буфер.
