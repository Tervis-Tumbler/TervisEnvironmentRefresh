#Requires -Modules TervisEnvironment,TervisStorage

function New-EnvironmentRefreshSnapshot{
    param(
        [ValidateSet(”DB_IMS”,“DB_MES”,"DB_ICMS","DB_Shipping","DB_Tervis_RMSHQ1","P-WCSDATA","ALL")]
        [String]$LUNName,

        [ValidateSet(”Delta”,“Epsilon”,"ALL")]
        [String]$EnvironmentName
    )
    $DATE = (get-date).tostring("yyyyMMdd")
    if($LUNName -eq "ALL"){
        $LUNList = $EnvironmentRefreshSnapshotListDetails.LUNName
    }
    else{$LUNList = $LUNName}
    if($EnvironmentName -eq "ALL"){
        $EnvironmentList = "Delta","Epsilon"
    }
    else{$EnvironmentList = $EnvironmentName}
    ForEach ($LUN in $LUNList){
        ForEach ($Environment in $EnvironmentList) {
            $EnvironmentPrefix = get-TervisEnvironmentPrefix -EnvironmentName $Environment
            $EnvironmentrefreshSnapshotDetails = Get-EnvironmentRefreshSnapshotListDetails -LUNName $LUN
            $SourceComputer = $EnvironmentrefreshSnapshotDetails.Computername
            $LUNID = $EnvironmentrefreshSnapshotDetails.LUNID
            $SnapshotName = "$($LUN)_$EnvironmentPrefix-$($SourceComputer)_$DATE"
            New-VNXLUNSnapshot -LUNID $LUNID -SnapshotName $SnapshotName -TervisStorageArraySelection $EnvironmentrefreshSnapshotDetails.SANLocation
        }
    }
}

function Get-EnvironmentRefreshSnapshotListDetails{
    param(
        [Parameter(Mandatory)][String]$LUNName
    )
    $EnvironmentRefreshSnapshotListDetails | Where LUNName -EQ $LUNName
}

$EnvironmentRefreshSnapshotListDetails = [pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1005"
    LUNName = "DB_IMS"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1004"
    LUNName = "DB_MES"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1769"
    LUNName = "DB_ICMS"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1001"
    LUNName = "DB_Shipping"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "30"
    LUNName = "DB_Tervis_RMSHQ1"
    SANLocation = "VNX5200"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1745"
    LUNName = "P-WCSDATA"
    SANLocation = "VNX5300"
}
