package ftpserver

import "strings"

const minWebcamImageSize = 10 * 1024 // 10KB

var imageExtensions = map[string]bool{
	".jpg":  true,
	".jpeg": true,
	".png":  true,
	".gif":  true,
	".bmp":  true,
	".webp": true,
	".tiff": true,
}

// ShouldAcceptFile validates that an FTP-uploaded file is an image of acceptable size.
func ShouldAcceptFile(filename string, fileSize int64) (bool, string) {
	filename = strings.ToLower(filename)

	ext := ""
	if idx := strings.LastIndex(filename, "."); idx != -1 {
		ext = filename[idx:]
	}

	if !imageExtensions[ext] {
		return false, "only image files accepted (.jpg, .jpeg, .png, .gif, .bmp, .webp, .tiff)"
	}

	if fileSize < minWebcamImageSize {
		return false, "image files must be at least 10KB"
	}

	return true, ""
}
