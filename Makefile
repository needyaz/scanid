# The same checks CI runs (.github/workflows/ci.yml), as make targets.
.PHONY: analyze test build-ios build-android

## flutter analyze
analyze:
	flutter pub get
	flutter analyze

## flutter test
test:
	flutter pub get
	flutter test

## The example app's iOS release build, unsigned (macOS)
build-ios:
	cd example && flutter pub get && flutter build ios --release --no-codesign

## The example app's Android debug build
build-android:
	cd example && flutter pub get && flutter build apk --debug
