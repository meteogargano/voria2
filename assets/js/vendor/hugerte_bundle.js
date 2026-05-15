import hugerte from "hugerte"

import "hugerte/models/dom"
import "hugerte/icons/default"
import "hugerte/themes/silver"
import "hugerte/skins/ui/oxide/skin.js"
import "hugerte/skins/ui/oxide/content.js"
import "hugerte/skins/content/default/content.js"
import "hugerte/plugins/advlist"
import "hugerte/plugins/autolink"
import "hugerte/plugins/autoresize"
import "hugerte/plugins/code"
import "hugerte/plugins/fullscreen"
import "hugerte/plugins/help"
import "hugerte/plugins/help/js/i18n/keynav/en.js"
import "hugerte/plugins/image"
import "hugerte/plugins/link"
import "hugerte/plugins/lists"
import "hugerte/plugins/media"
import "hugerte/plugins/preview"
import "hugerte/plugins/searchreplace"
import "hugerte/plugins/table"
import "hugerte/plugins/visualblocks"
import "hugerte/plugins/wordcount"

let hugertePromise

export function loadHugeRte() {
  hugertePromise ||= Promise.resolve(hugerte)
  return hugertePromise
}
