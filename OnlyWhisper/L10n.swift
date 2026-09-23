import Foundation

func t(_ english: String, _ german: String) -> String {
    if Locale.current.language.languageCode?.identifier == "de" {
        return german
    }
    return english
}
