$codes = @(
  "credit1000",
  "proplanplus",
  "proplanminus",
  "premiunplanplus",
  "premiunplanminus"
)

function Get-Sha256Hex([string]$value) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($value)
  $hashBytes = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

Write-Host "Coupon codeHash (sha256(lowercase(code)))"
Write-Host "-------------------------------------"
foreach ($code in $codes) {
  $hash = Get-Sha256Hex($code.ToLower())
  Write-Host ("{0} => {1}" -f $code, $hash)
}

