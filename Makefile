APP      := LangSwitcher
CONFIG   ?= release
BUNDLE   := build/$(APP).app
BINDIR    = $(shell swift build -c $(CONFIG) --show-bin-path)
BUNDLE_ID := com.langswitcher.app

.PHONY: all build app install run stop clean

all: app

build:
	swift build -c $(CONFIG)

## Собирает .app-бандл: SwiftPM даёт только исполняемый файл,
## а строка меню, LSUIElement и права доступа требуют полноценного бандла.
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINDIR)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	codesign --force --sign - --identifier $(BUNDLE_ID) $(BUNDLE)
	@echo "Готово: $(BUNDLE)"

## После установки собранная копия удаляется: две одинаковые программы в разных
## местах превращаются в две неразличимые строки списка «Универсального доступа».
install: app
	-pkill -x $(APP) || true
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/$(APP).app
	codesign --force --sign - --identifier $(BUNDLE_ID) /Applications/$(APP).app
	rm -rf $(BUNDLE)
	@echo "Установлено в /Applications/$(APP).app"
	@echo
	@echo "ВАЖНО: подпись ad-hoc привязана к хешу бинарника, поэтому после пересборки"
	@echo "выданный доступ перестаёт действовать. Сбросьте и выдайте его заново:"
	@echo "    tccutil reset Accessibility $(BUNDLE_ID)"
	@echo "    open /Applications/$(APP).app"

run: app
	-pkill -x $(APP) || true
	open $(BUNDLE)

stop:
	-pkill -x $(APP) || true

clean:
	rm -rf build .build
