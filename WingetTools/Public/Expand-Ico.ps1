function Expand-Ico {
    <#
    .SYNOPSIS
        Splits a Windows .ico file into its individual frames, preserving the raw
        bytes of each embedded image.
    .DESCRIPTION
        Parses the ICO container directly per the documented file layout and writes
        each frame as .png, .bmp, or single-frame .ico.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName', 'PSPath')]
        [string[]] $Path,

        [string] $OutDir,

        [ValidateSet('Bmp', 'Ico')]
        [string] $DibFormat = 'Bmp',

        [switch] $Force
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # PNG signature: 89 50 4E 47 0D 0A 1A 0A
        $script:PngSignature = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

        function Test-IsPng {
            param([byte[]] $Bytes)
            if ($Bytes.Length -lt 8) { return $false }
            for ($i = 0; $i -lt 8; $i++) {
                if ($Bytes[$i] -ne $script:PngSignature[$i]) { return $false }
            }
            return $true
        }

        function Write-LE-UInt16 {
            param([System.IO.BinaryWriter] $Writer, [uint16] $Value)
            $Writer.Write([uint16] $Value)
        }

        function Write-LE-UInt32 {
            param([System.IO.BinaryWriter] $Writer, [uint32] $Value)
            $Writer.Write([uint32] $Value)
        }

        function Write-SingleFrameIco {
            param(
                [string] $OutFile,
                [byte] $BWidth,
                [byte] $BHeight,
                [byte] $BColorCount,
                [byte] $BReserved,
                [uint16] $WPlanes,
                [uint16] $WBitCount,
                [byte[]] $Payload
            )

            $imageOffset = [uint32] 22
            $bytesInRes  = [uint32] $Payload.Length

            $stream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create,
                                              [System.IO.FileAccess]::Write,
                                              [System.IO.FileShare]::None)
            try {
                $bw = [System.IO.BinaryWriter]::new($stream)
                try {
                    Write-LE-UInt16 $bw 0
                    Write-LE-UInt16 $bw 1
                    Write-LE-UInt16 $bw 1

                    $bw.Write([byte] $BWidth)
                    $bw.Write([byte] $BHeight)
                    $bw.Write([byte] $BColorCount)
                    $bw.Write([byte] $BReserved)
                    Write-LE-UInt16 $bw $WPlanes
                    Write-LE-UInt16 $bw $WBitCount
                    Write-LE-UInt32 $bw $bytesInRes
                    Write-LE-UInt32 $bw $imageOffset

                    $bw.Write($Payload)
                    $bw.Flush()
                } finally {
                    $bw.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        }

        function Write-DibAsBmp {
            param(
                [string] $OutFile,
                [int] $Width,
                [int] $Height,
                [uint16] $WBitCount,
                [byte[]] $Payload
            )

            if ($Payload.Length -lt 16) {
                throw "DIB payload too small ($($Payload.Length) bytes) to contain BITMAPINFOHEADER."
            }

            $biSize = [System.BitConverter]::ToUInt32($Payload, 0)
            if ($biSize -lt 16 -or $biSize -gt 124 -or $biSize -gt $Payload.Length) {
                throw "DIB has implausible biSize=$biSize."
            }

            $paletteEntries = 0
            if ($WBitCount -le 8) {
                $biClrUsed = [System.BitConverter]::ToUInt32($Payload, 32)
                $paletteEntries = if ($biClrUsed -ne 0) { [int] $biClrUsed } else { 1 -shl [int] $WBitCount }
            }
            $paletteBytes = $paletteEntries * 4

            $xorRowBytes = [int] ((([int] $WBitCount * $Width + 31) -band -bnot 31) / 8)
            $xorBytes    = $xorRowBytes * $Height

            $dibKeepBytes = [int] $biSize + $paletteBytes + $xorBytes

            if ($dibKeepBytes -gt $Payload.Length) {
                throw ("DIB payload too small for declared geometry: need {0} bytes (header={1} + palette={2} + pixels={3}), have {4}." `
                    -f $dibKeepBytes, $biSize, $paletteBytes, $xorBytes, $Payload.Length)
            }

            $bfOffBits = [uint32] (14 + [int] $biSize + $paletteBytes)
            $bfSize    = [uint32] (14 + $dibKeepBytes)

            $patched = New-Object byte[] $dibKeepBytes
            [System.Buffer]::BlockCopy($Payload, 0, $patched, 0, $dibKeepBytes)
            $heightBytes = [System.BitConverter]::GetBytes([int32] $Height)
            [System.Buffer]::BlockCopy($heightBytes, 0, $patched, 8, 4)

            $stream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create,
                                              [System.IO.FileAccess]::Write,
                                              [System.IO.FileShare]::None)
            try {
                $bw = [System.IO.BinaryWriter]::new($stream)
                try {
                    $bw.Write([byte] 0x42)
                    $bw.Write([byte] 0x4D)
                    Write-LE-UInt32 $bw $bfSize
                    Write-LE-UInt16 $bw 0
                    Write-LE-UInt16 $bw 0
                    Write-LE-UInt32 $bw $bfOffBits

                    $bw.Write($patched)
                    $bw.Flush()
                } finally {
                    $bw.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        }

        function Expand-OneIco {
            param(
                [string] $IcoPath,
                [string] $TargetDir,
                [string] $DibFormat,
                [switch] $Force
            )

            $bytes = [System.IO.File]::ReadAllBytes($IcoPath)
            if ($bytes.Length -lt 6) {
                throw "File '$IcoPath' is too small to be an ICO ($($bytes.Length) bytes)."
            }

            $reserved = [System.BitConverter]::ToUInt16($bytes, 0)
            $type     = [System.BitConverter]::ToUInt16($bytes, 2)
            $count    = [System.BitConverter]::ToUInt16($bytes, 4)

            if ($reserved -ne 0) {
                throw "File '$IcoPath' has non-zero idReserved ($reserved); not a valid ICO."
            }
            if ($type -ne 1) {
                throw "File '$IcoPath' has idType=$type (expected 1 for ICO; 2 = CUR is not supported)."
            }
            if ($count -eq 0) {
                Write-Warning "File '$IcoPath' declares zero frames."
                return
            }

            $needed = 6 + ($count * 16)
            if ($bytes.Length -lt $needed) {
                throw "File '$IcoPath' is truncated: need $needed bytes for directory, have $($bytes.Length)."
            }

            if (-not (Test-Path -LiteralPath $TargetDir)) {
                New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
            }

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($IcoPath)

            for ($i = 0; $i -lt $count; $i++) {
                $entryOffset = 6 + ($i * 16)

                $bWidth      = $bytes[$entryOffset + 0]
                $bHeight     = $bytes[$entryOffset + 1]
                $bColorCount = $bytes[$entryOffset + 2]
                $bReserved   = $bytes[$entryOffset + 3]
                $wPlanes     = [System.BitConverter]::ToUInt16($bytes, $entryOffset + 4)
                $wBitCount   = [System.BitConverter]::ToUInt16($bytes, $entryOffset + 6)
                $dwBytesInRes  = [System.BitConverter]::ToUInt32($bytes, $entryOffset + 8)
                $dwImageOffset = [System.BitConverter]::ToUInt32($bytes, $entryOffset + 12)

                $width  = if ($bWidth  -eq 0) { 256 } else { [int] $bWidth  }
                $height = if ($bHeight -eq 0) { 256 } else { [int] $bHeight }

                if ($dwImageOffset + $dwBytesInRes -gt [uint32] $bytes.Length) {
                    Write-Warning ("Frame #{0} in '{1}' is truncated (offset={2}, size={3}, file={4}); skipping." `
                        -f $i, $IcoPath, $dwImageOffset, $dwBytesInRes, $bytes.Length)
                    continue
                }

                $payload = New-Object byte[] $dwBytesInRes
                [System.Buffer]::BlockCopy($bytes, [int] $dwImageOffset, $payload, 0, [int] $dwBytesInRes)

                $isPng = Test-IsPng -Bytes $payload
                if ($isPng) {
                    $format = 'PNG'
                    $ext    = 'png'
                } elseif ($DibFormat -eq 'Bmp') {
                    $format = 'DIB'
                    $ext    = 'bmp'
                } else {
                    $format = 'DIB'
                    $ext    = 'ico'
                }

                $outName = '{0}_{1:D2}_{2}x{3}_{4}bpp.{5}' -f $baseName, $i, $width, $height, $wBitCount, $ext
                $outPath = Join-Path -Path $TargetDir -ChildPath $outName

                if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
                    throw "Output file '$outPath' already exists. Use -Force to overwrite."
                }

                if ($isPng) {
                    [System.IO.File]::WriteAllBytes($outPath, $payload)
                } elseif ($DibFormat -eq 'Bmp') {
                    Write-DibAsBmp -OutFile $outPath `
                        -Width $width -Height $height `
                        -WBitCount $wBitCount -Payload $payload
                } else {
                    Write-SingleFrameIco -OutFile $outPath `
                        -BWidth $bWidth -BHeight $bHeight `
                        -BColorCount $bColorCount -BReserved $bReserved `
                        -WPlanes $wPlanes -WBitCount $wBitCount `
                        -Payload $payload
                }

                [pscustomobject] @{
                    SourceIco    = $IcoPath
                    Index        = $i
                    Width        = $width
                    Height       = $height
                    BitCount     = [int] $wBitCount
                    Planes       = [int] $wPlanes
                    ColorCount   = [int] $bColorCount
                    Format       = $format
                    PayloadBytes = [int] $dwBytesInRes
                    OutPath      = $outPath
                }
            }
        }
    }

    process {
        foreach ($p in $Path) {
            $resolved = Resolve-Path -LiteralPath $p -ErrorAction Stop
            foreach ($r in $resolved) {
                $item = Get-Item -LiteralPath $r.ProviderPath
                $files = if ($item.PSIsContainer) {
                    Get-ChildItem -LiteralPath $item.FullName -Filter *.ico -File
                } else {
                    @($item)
                }

                foreach ($file in $files) {
                    $target = if ($PSBoundParameters.ContainsKey('OutDir') -and $OutDir) {
                        $OutDir
                    } else {
                        Join-Path -Path $file.DirectoryName `
                                  -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) + '.frames')
                    }

                    Write-Verbose "Expanding '$($file.FullName)' into '$target' (DibFormat=$DibFormat)"
                    Expand-OneIco -IcoPath $file.FullName -TargetDir $target -DibFormat $DibFormat -Force:$Force
                }
            }
        }
    }
}
