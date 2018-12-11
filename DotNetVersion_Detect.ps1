# Determine the version of .net 4 framework by querying Registry HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full for Value of Release 
# 
# Based on https://msdn.microsoft.com/en-us/library/hh925568(v=vs.110).aspx
#
#
#
$Netver = (Get-ItemProperty ‘HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full’ -Name Release).Release
If ($Netver -lt 378389)
{
Write-Host “.NET Framework version OLDER than 4.5” -foregroundcolor yellow
}
ElseIf ($Netver -eq 378389)
{
Write-Host “.NET Framework 4.5” -foregroundcolor red
}
ElseIf ($Netver -le 378675)
{
Write-Host “.NET Framework 4.5.1 installed with Windows 8.1” -foregroundcolor red
}
ElseIf ($Netver -le 378758)
{
Write-Host “.NET Framework 4.5.1 installed on Windows 8, Windows 7 SP1, or Windows Vista SP2” -foregroundcolor red
}
ElseIf ($Netver -le 379893)
{
Write-Host “.NET Framework 4.5.2” -foregroundcolor red
}
ElseIf ($Netver -le 393295)
{
Write-Host “.NET Framework 4.6 installed with Windows 10” -foregroundcolor red 
}
ElseIf ($Netver -le 393297)
{
Write-Host “.NET Framework 4.6 installed on all other Windows OS versions” -foregroundcolor red
}
ElseIf ($Netver -le 394254)
{
Write-Host “.NET Framework 4.6.1 installed on Windows 10” -foregroundcolor red
}
ElseIf ($Netver -le 394271)
{
Write-Host “.NET Framework 4.6.1 installed on all other Windows OS versions” -foregroundcolor red
}
ElseIf ($Netver -le 394294)
{
Write-Host “.NET Framework 4.6.1 installed on all other Windows OS versions (With required Hotfix)” -foregroundcolor red
}
ElseIf ($Netver -le 394802)
{
Write-Host “.NET Framework 4.6.2 installed on Windows 10 Anniversary Update” -foregroundcolor red
}
ElseIf ($Netver -le 394806)
{
Write-Host “.NET Framework 4.6.2 installed on all other Windows OS versions” -foregroundcolor red
}
ElseIf ($Netver -le 460798)
{
Write-Host “.NET Framework 4.7.0 installed on Windows 10 Creators Update” -foregroundcolor red
}
ElseIf ($Netver -le 460805)
{
Write-Host “.NET Framework 4.7.0 installed on all other Windows OS versions” -foregroundcolor red
}
ElseIf ($Netver -le 461308)
{
Write-Host “.NET Framework 4.7.1 installed on Windows 10 Fall Creators Update” -foregroundcolor red
}
ElseIf ($Netver -le 461310)
{
Write-Host “.NET Framework 4.7.1 installed on all other Windows OS versions” -foregroundcolor red
}