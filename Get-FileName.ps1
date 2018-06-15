Function Get-FileName($InitialDirectory, $Filename, $FilenameDescription ,$FileType, $FileTypeDescription, $Title)
{  
 [Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

 if (!$Filename) 
    {
    $Filename = "*"
    $FilenameDescription = "Any file name of type"
    }

 if (!$FileType) 
    {
    $FileType = "*"
    $FileTypeDescription = "any"
    }
 

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.Title = $Title
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.filter = "$($FilenameDescription) $($FileTypeDescription) ($($Filename).$($FileType)) | $($Filename).$($FileType)"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
} #end function Get-FileName
