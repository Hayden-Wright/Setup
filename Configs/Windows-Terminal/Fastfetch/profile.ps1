# Профиль PowerShell: UTF-8 + Fastfetch.
# Блок ниже добавлен установщиком из репозитория Setup.
# >>> Setup: fastfetch >>>
try {
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    chcp 65001 > $null
} catch {}

Clear-Host

if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch -c "$env:USERPROFILE/.config/fastfetch/config.jsonc"
}
# <<< Setup: fastfetch <<<
