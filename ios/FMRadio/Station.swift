import Foundation

struct Station: Identifiable, Hashable {
    let name: String
    let stream: URL
    let metadata: URL
    var id: URL { stream }
}

struct StationGroup: Identifiable {
    let title: String
    let stations: [Station]
    var id: String { title }
}

private func station(_ name: String, _ stream: String, _ meta: String) -> Station {
    Station(
        name: name,
        stream: URL(string: "https://\(stream)")!,
        metadata: URL(string: "https://o.tavrmedia.ua/\(meta)")!
    )
}

let stationGroups: [StationGroup] = [
    StationGroup(title: "KISS FM", stations: [
        station("KISS FM", "online.kissfm.ua/KissFM_HD", "kiss"),
        station("KISS FM Ukrainian", "online.kissfm.ua/KissFM_Ukr_HD", "kissukr"),
        station("KISS FM Deep", "online.kissfm.ua/KissFM_Deep_HD", "kissdeep"),
        station("KISS FM Digital", "online.kissfm.ua/KissFM_Digital_HD", "kissdigital"),
    ]),
    StationGroup(title: "Radio Relax", stations: [
        station("Ефір Радіо Relax", "online.radiorelax.ua/RadioRelax_HD", "relax"),
        station("Relax Українською", "online.radiorelax.ua/RadioRelax_Ukr_HD", "relaxukr"),
        station("Relax International", "online.radiorelax.ua/RadioRelax_Int_HD", "relaxint"),
        station("Relax Cafe", "online.radiorelax.ua/RadioRelax_Cafe_HD", "relaxcafe"),
        station("Relax Instrumental", "online.radiorelax.ua/RadioRelax_Instrumental_HD", "relaxinstrumental"),
    ]),
    StationGroup(title: "Хіт FM", stations: [
        station("Ефір Хіт FM", "online.hitfm.ua/HitFM_HD", "hit"),
        station("Хіт FM Українські хіти", "online.hitfm.ua/HitFM_Ukr_HD", "hitu"),
        station("Хіт FM Найбільші хіти", "online.hitfm.ua/HitFM_Best_HD", "hitb"),
        station("Хіт FM Сучасні хіти", "online.hitfm.ua/HitFM_Top_HD", "hitt"),
    ]),
    StationGroup(title: "Мелодія FM", stations: [
        station("Ефір Мелодія FM", "online.melodiafm.ua/MelodiaFM_HD", "melodia"),
        station("Мелодія FM International", "online.melodiafm.ua/MelodiaFM_Int_HD", "melodiaint"),
        station("Мелодія FM Disco", "online.melodiafm.ua/MelodiaFM_Disco_HD", "melodiad"),
        station("Мелодія FM Romantic", "online.melodiafm.ua/MelodiaFM_Romantic_HD", "melodiar"),
    ]),
    StationGroup(title: "Radio ROKS", stations: [
        station("Ефір Radio ROKS", "online.radioroks.ua/RadioROKS_HD", "roks"),
        station("Radio ROKS Український рок", "online.radioroks.ua/RadioROKS_Ukr_HD", "roksukr"),
        station("Radio ROKS Новий Рок", "online.radioroks.ua/RadioROKS_NewRock_HD", "roksnew"),
        station("Radio ROKS Classic Rock", "online.radioroks.ua/RadioROKS_ClassicRock_HD", "rokscla"),
        station("Radio ROKS Hard'n'Heavy", "online.radioroks.ua/RadioROKS_HardnHeavy_HD", "rokshar"),
        station("Radio ROKS Рок-Балади", "online.radioroks.ua/RadioROKS_Ballads_HD", "roksbal"),
    ]),
    StationGroup(title: "Інші", stations: [
        station("Flash Radio", "online.radioplayer.ua/FlashRadio_HD", "radio3flash"),
        station("Radio Gold", "online.radioplayer.ua/RadioGold_HD", "radio3gold"),
        station("Радіо Інді.UA", "online.radioplayer.ua/RadioIndieUA_HD", "radio3indieua"),
        station("Радіо Байрактар", "online.radiobayraktar.ua/RadioBayraktar_HD", "radio3bayraktar"),
        station("Ефір Наше Радіо", "online.nasheradio.ua/NasheRadio_HD", "nasheradio"),
        station("Наше Радіо УкрТоп100", "online.nasheradio.ua/NasheRadio_Ukr_HD", "nasheradio3ukr"),
        station("Гуляй Радіо", "online.radioplayer.ua/GuliayRadio_HD", "radio3guliay"),
    ]),
]
