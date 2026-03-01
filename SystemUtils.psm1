#
# SystemUtils powershell module
#

function FatalError {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$out
    )
    throw "ERROR: $out"
}

function Error {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$out
    )
    Write-Host -ForegroundColor RED "ERROR: $out"
}

function Warning {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$out
    )
    Write-Host -ForegroundColor RED "WARNING: $out"
}

function Info {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$out
    )
    Write-Host -ForegroundColor Green "Info: $out"
}

function Remove-File {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$filename
    )
    if (Test-Path $filename -PathType Leaf) {
        Remove-Item $filename
    }
}

function Escape_Quotes {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$str
    )
    $a = $str -replace '"',"'"
    return $a
}

function Round_number {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$num,
        [Parameter(Mandatory = $true, Position = 2)]
        [int]$r
    )
    $a = $r * ([int]([math]::floor(($num + ($r/2))/$r)))
    return [int]$a
}

function Find_Process {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$proc,
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$arg_info=""
    )
    $a = Get-Process -Name $proc -ErrorAction Ignore
    if ($a -eq $null) {
        return $null
    }
    $ids = $a.id
    foreach ($id in $ids) {
        if (Is_Linux) {
            $t = Get-Content "/proc/$id/cmdline"
            if (($arg_info -eq "") -or ($t -like "*$arg_info*")) {
                Write-Host $t
                return Get-Process -id $id
            }
        }
        else {
            throw "Windows is not implemented for Find_process"
        }
    }
    return $null
}
