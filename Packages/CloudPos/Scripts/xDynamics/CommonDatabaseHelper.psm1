. "$PSScriptRoot\CommonRetailDSCConfiguration.ps1"

$DSCModuleRoot = Get-DSCModuleRoot

Import-Module "$DSCModuleRoot\xDynamics\DeploymentHelper.psm1" -DisableNameChecking

#region local functions
function Invoke-SqlCommand{
    param($dbServer,$dbName,$dbUser,$dbPassword,$windowsAuth=$true,$scriptBlock)
    $connectionstring_windowsauth="server=$dbServer;Database=$dbName;Trusted_Connection=true"
    $connectionstring_sqlauth="Server=$dbServer;Database=$dbName;User Id=$dbUser;Password=`"$dbPassword`""
    if($windowsAuth){
        $sqlConnection=New-Object System.Data.SqlClient.SqlConnection $connectionstring_windowsauth
        Trace-Debug "Sql connection string with windows auth:'$connectionstring_windowsauth'"
        Write-Verbose "Sql connection string with windows auth:'$connectionstring_windowsauth'"
    }
    else{
        $sqlConnection=New-Object System.Data.SqlClient.SqlConnection $connectionstring_sqlauth
        Trace-Debug "Sql connection string with sql auth:'$connectionstring_sqlauth'"
        Write-Verbose "Sql connection string with sql auth:'$connectionstring_sqlauth'"
    }

    try{
        $sqlConnection.Open()
        $sqlCommand=$sqlConnection.CreateCommand()
        $result=Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $sqlCommand
        $sqlConnection.Close()
        return $result
    }
    catch{
        throw
    }
    finally{
         if($sqlConnection -ne $null -and $sqlConnection.State -eq [System.Data.ConnectionState]::Open){
            $sqlConnection.Close()
         }
    }
}

function New-User{
    param($dbServer, $dbName, $dbUser, $dbPassword)

    $codeblock={
        try
        {
            $sqlcmd="IF NOT EXISTS(SELECT NAME FROM sys.server_principals WHERE NAME = '$dbUser') CREATE LOGIN $dbUser WITH PASSWORD = '$dbPassword'"
            Trace-Debug "Running sql cmd:'$sqlcmd' using Windows auth"
            Write-Verbose "Running sql cmd:'$sqlcmd' using Windows auth"
            Invoke-SqlCommand $dbServer $dbName $dbUser $dbPassword $true {
                $sqlCommand.CommandText = $sqlcmd
                $sqlCommand.ExecuteScalar()
            }

            Trace-Info "Granting sysadmin rights to the user '$dbUser'."
            Write-Verbose "Granting sysadmin rights to the user '$dbUser'."
            $sqlcmd="SP_ADDSRVROLEMEMBER '$dbUser', 'sysadmin'"
            Trace-Debug "Running sql cmd:'$sqlcmd' using Windows auth"
            Write-Verbose "Running sql cmd:'$sqlcmd' using Windows auth"
            Invoke-SqlCommand $dbServer $dbName $dbUser $dbPassword $true {
                $sqlCommand.CommandText = $sqlcmd
                $sqlCommand.ExecuteScalar()
            }

            $true
        }
        catch{
            throw
        }
    }

    ExecuteWith-Retry $codeblock "Create sql user"
}

function Create-Database{
    param($dbServer,$dbName,$dbUser,$dbPassword)

    $codeblock={
        try
        {
            # create database
            $sqlcmd="IF NOT EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = N'$dbName') CREATE DATABASE [$dbName]"
            Invoke-SqlCommand $dbServer $global:MasterDB $dbUser $dbPassword $false {
                $sqlCommand.CommandText = $sqlcmd
                $sqlCommand.CommandTimeout=0
                $sqlCommand.ExecuteNonQuery()
            }

            $true
        }
        catch{
            throw
        }
    }

    ExecuteWith-Retry $codeblock "Create database"
}

function Apply-SqlScript{
    param($dbServer,$dbName,$dbUser,$dbPassword,$scriptFile)
    $codeblock={
        try{         
            # apply a sql script  file            
            Trace-Debug "Running sql script file:'$scriptFile' with sql auth"
            Write-Verbose "Running sql script file:'$scriptFile' with sql auth"
            $result=Invoke-SqlCmd -ServerInstance $dbServer -Database  $dbName -Username $dbUser -Password $dbPassword -InputFile $scriptFile

            return $true
        }
        catch{
            throw
        }
    }

    ExecuteWith-Retry $codeblock "Restore database"
}

function ExecuteWith-Retry($codeBlock, $blockMessage, $maxRetry, $sleepTime)
{    
    Trace-Debug "$blockMessage`: Starting execution with retry"
    Write-Verbose "$blockMessage`: Starting execution with retry"
    if ($maxRetry -eq $null -or $maxRetry -le 0)
    {
        $maxRetry = 5
    }

    if ($sleepTime -eq $null -or $sleepTime -lt 0)
    {
        $sleepTime = 30
    }

    $retry = 0
    for($retry = 0; $retry -lt $maxRetry; $retry++)
    {
        try
        {
            &$codeBlock
            break;
        }
        catch
        {
            $exception = $_
            $message = "Exception during $blockMessage`:$exception"
            if($retry -lt $maxRetry-1)
            {
                Trace-Error $message
                Write-Verbose $message
                Trace-Info "Sleeping 30s before retrying"
                Write-Verbose "Sleeping 30s before retrying"
                Sleep $sleepTime
            }
            else
            {
                $message = "Max retry count reached during $blockMessage`:$exception"
                Trace-Error $message
                throw $exception
            }
        }
    }

    $retry++
    Trace-Debug "$blockMessage`: Completed execution in $retry iterations"
}

#endregion

Export-ModuleMember -Function * -Alias *
# SIG # Begin signature block
# MIIdvAYJKoZIhvcNAQcCoIIdrTCCHakCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU1qGAa9f0N4+vhRjPo1+LoZQo
# yjqgghhkMIIEwzCCA6ugAwIBAgITMwAAAK7sP622i7kt0gAAAAAArjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwNTAzMTcxMzI1
# WhcNMTcwODAzMTcxMzI1WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkI4RUMtMzBBNC03MTQ0MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxTU0qRx3sqZg
# 8GN4YCrqA1CzmYPp8+U/MG7axHXPZGdMvNbRSPl29ba88jCYRut/6p5OjvCGNcRI
# MPWKFMqKVeY8zUoQNp46jYsXenl4vTAgJ2cUCeaGy9vxLYTGuXtaChn+jIpPuR6x
# UQ60Y44M2jypsbcQZYc6Oukw4co+CIw8fKqxPcDjdm1c/gyzVnhSYTXsv8S0NBwl
# iuhNCNE4D8b0LNj7Exj5zfVYGvP6Z+JtGY7LT+7caUCT0uItKlE0D/iDvlY5zLrb
# luUb4WLUBpglMw7bU0BSAcvcNx0XyV7+AdcmhiFQGt4pZjbVzOsXs3POWHTq4/KX
# RmtGHKfvMwIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFBw4ctJakrpBibpB9TJkYJsJ
# gGBUMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAAAZsVbJVNFZUNMcXRxKeelc1DgiQHLC60Sika98OwDFXomY
# akk6yvE+fJ3DICnDUK9kmf83sYTOQ5Y7h3QzwHcPdyhLPHSBBmuPklj6jcWGuvHK
# pUuP9PTjyKBw0CPZ1PTO1Jc5RjsQYvxqu01+G5UvZolnM6Ww7QpmBoDEyze5J+dg
# GwrWMhIKDzKLV9do6R5ouZQvLvV7bjH50AX2tK2n3zpZYvAl/LayLHFNIO7A2DQ1
# VzWa3n2yyYvameaX1NkSLA32PqjAXykmkDfHQ6DFVuDV4nqrNI+s14EJgMQy8DzU
# 9X7+KIkCzLFNq/bc2WDo15qsQiACPVSKY1IOGiIwggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TCCBhAwggP4
# oAMCAQICEzMAAABkR4SUhttBGTgAAAAAAGQwDQYJKoZIhvcNAQELBQAwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMTAeFw0xNTEwMjgyMDMxNDZaFw0xNzAx
# MjgyMDMxNDZaMIGDMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MQ0wCwYDVQQLEwRNT1BSMR4wHAYDVQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24w
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCTLtrY5j6Y2RsPZF9NqFhN
# FDv3eoT8PBExOu+JwkotQaVIXd0Snu+rZig01X0qVXtMTYrywPGy01IVi7azCLiL
# UAvdf/tqCaDcZwTE8d+8dRggQL54LJlW3e71Lt0+QvlaHzCuARSKsIK1UaDibWX+
# 9xgKjTBtTTqnxfM2Le5fLKCSALEcTOLL9/8kJX/Xj8Ddl27Oshe2xxxEpyTKfoHm
# 5jG5FtldPtFo7r7NSNCGLK7cDiHBwIrD7huTWRP2xjuAchiIU/urvzA+oHe9Uoi/
# etjosJOtoRuM1H6mEFAQvuHIHGT6hy77xEdmFsCEezavX7qFRGwCDy3gsA4boj4l
# AgMBAAGjggF/MIIBezAfBgNVHSUEGDAWBggrBgEFBQcDAwYKKwYBBAGCN0wIATAd
# BgNVHQ4EFgQUWFZxBPC9uzP1g2jM54BG91ev0iIwUQYDVR0RBEowSKRGMEQxDTAL
# BgNVBAsTBE1PUFIxMzAxBgNVBAUTKjMxNjQyKzQ5ZThjM2YzLTIzNTktNDdmNi1h
# M2JlLTZjOGM0NzUxYzRiNjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzcitW2oynUC
# lTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEGCCsGAQUF
# BwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0MAwGA1Ud
# EwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjiDGRDHd1crow7hSS1nUDWvWas
# W1c12fToOsBFmRBN27SQ5Mt2UYEJ8LOTTfT1EuS9SCcUqm8t12uD1ManefzTJRtG
# ynYCiDKuUFT6A/mCAcWLs2MYSmPlsf4UOwzD0/KAuDwl6WCy8FW53DVKBS3rbmdj
# vDW+vCT5wN3nxO8DIlAUBbXMn7TJKAH2W7a/CDQ0p607Ivt3F7cqhEtrO1Rypehh
# bkKQj4y/ebwc56qWHJ8VNjE8HlhfJAk8pAliHzML1v3QlctPutozuZD3jKAO4WaV
# qJn5BJRHddW6l0SeCuZmBQHmNfXcz4+XZW/s88VTfGWjdSGPXC26k0LzV6mjEaEn
# S1G4t0RqMP90JnTEieJ6xFcIpILgcIvcEydLBVe0iiP9AXKYVjAPn6wBm69FKCQr
# IPWsMDsw9wQjaL8GHk4wCj0CmnixHQanTj2hKRc2G9GL9q7tAbo0kFNIFs0EYkbx
# Cn7lBOEqhBSTyaPS6CvjJZGwD0lNuapXDu72y4Hk4pgExQ3iEv/Ij5oVWwT8okie
# +fFLNcnVgeRrjkANgwoAyX58t0iqbefHqsg3RGSgMBu9MABcZ6FQKwih3Tj0DVPc
# gnJQle3c6xN3dZpuEgFcgJh/EyDXSdppZzJR4+Bbf5XA/Rcsq7g7X7xl4bJoNKLf
# cafOabJhpxfcFOowMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkqhkiG9w0B
# AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAG
# A1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTEw
# HhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBT
# aWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# q/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03a8YS2Avw
# OMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akrrnoJr9eW
# WcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0RrrgOGSsbmQ1
# eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy4BI6t0le
# 2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9sbKvkjh+
# 0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAhdCVfGCi2
# zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8kA/DRelsv
# 1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTBw3J64HLn
# JN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmnEyimp31n
# gOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90lfdu+Hgg
# WCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0wggHpMBAG
# CSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2oynUClTAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/
# BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBaBgNVHR8E
# UzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsGAQUFBwEB
# BFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNVHSAEgZcw
# gZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsGAQUFBwIC
# MDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABlAG0AZQBu
# AHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKbC5YR4WOS
# mUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11lhJB9i0ZQ
# VdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6I/MTfaaQ
# dION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0wI/zRive
# /DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560STkKxgrC
# xq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQamASooPoI/
# E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGaJ+HNpZfQ
# 7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ahXJbYANah
# Rr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA9Z74v2u3
# S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33VtY5E90Z1W
# Tk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr/Xmfwb1t
# bWrJUnMTDXpQzTGCBMIwggS+AgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcg
# UENBIDIwMTECEzMAAABkR4SUhttBGTgAAAAAAGQwCQYFKw4DAhoFAKCB1jAZBgkq
# hkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGC
# NwIBFTAjBgkqhkiG9w0BCQQxFgQUZH2RH/7JPBm1E+O5trwx8G4UCrowdgYKKwYB
# BAGCNwIBDDFoMGagNIAyAEMAbwBtAG0AbwBuAEQAYQB0AGEAYgBhAHMAZQBIAGUA
# bABwAGUAcgAuAHAAcwBtADGhLoAsaHR0cDovL3d3dy5NaWNyb3NvZnQuY29tL01p
# Y3Jvc29mdER5bmFtaWNzLyAwDQYJKoZIhvcNAQEBBQAEggEAR272yF/BYpWHTn74
# Ctc5AqPUNuevYaIlP2HLHGdj+J6IDNFqLv5UB55rsxZedDyi8AZ4JGGtf8Mz5/RW
# 2mOBmkAnvKQgt9kZvwvqodE/y8LFQrJLc+FtnPDC9uNO03GIyxctUVxDKfQmV+d2
# QD0HWcVD+3aUTQEnb+XF3DQGbplF5oz8Qb3tUcaIYVp8KEKOUTOXxjdoKtLr/x+4
# qxZifCskdr/iAdIV942fARIMidczVlWfzW4bhYNY/SWpD6yzhLWlobBoK2QddOn0
# Je/6Tt8QzSVXGUMbFnRSKdiSXbqZ+Vtvl0VCWd5mItwvsvBi+SKkrT921z10Ck4m
# NLCyeaGCAigwggIkBgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhNaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0ECEzMAAACu7D+ttou5LdIAAAAAAK4wCQYFKw4DAhoFAKBd
# MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE2MDcy
# MTIxMDcxOFowIwYJKoZIhvcNAQkEMRYEFCVznxdfzqetupmio3guCofUAXqTMA0G
# CSqGSIb3DQEBBQUABIIBAAC6vwri18KkWyozFpkEX9BgTDfcHEVNu0vZmucdKYN2
# +stFkKkdGVVMtda0ZXHKGtCZFQ9004DjWyreGLJqb10qmjzpBWb5qmZzWI2+3RP3
# i2fo1Xh9G/jiXhJX6IRfWjTQJuiRoD6NZLrVEWWmbyung6Z4WUHVbJaaRZ8M+iSS
# g++klA9Oc8jWZEG4gEUR6cMHvQ67v3uFcrcHKXJyokHDskmbg+jQ8exGtF5ZP+q7
# Ftx/aKhQ4TsKT6eh4bHmBBKD1aWfxuh8t8sleA2v9U0HBa5l9XBhfRN1uVPnvXWk
# dkgiCnv7Y23zqVAMXEwWzScSWMeZp9Z5Ft1lklcY/bU=
# SIG # End signature block
