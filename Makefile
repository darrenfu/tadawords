.PHONY: generate format lint test check

generate:
	xcodegen generate --spec project.yml

format:
	swift format format --configuration .swift-format --in-place --parallel --recursive Sources Tests Apps

lint:
	swift format lint --configuration .swift-format --strict --parallel --recursive Sources Tests Apps

test:
	swift test

check: lint test
