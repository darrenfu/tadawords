.PHONY: generate format lint test test-automation check

generate:
	./Scripts/generate-xcode-project.sh

format:
	swift format format --configuration .swift-format --in-place --parallel --recursive Sources Tests Apps

lint:
	swift format lint --configuration .swift-format --strict --parallel --recursive Sources Tests Apps

test:
	swift test

test-automation:
	python3 -m unittest discover -s Automation/issue-agent/tests -v
	python3 -m py_compile Automation/issue-agent/issue_agent.py
	plutil -lint Automation/issue-agent/com.tadawords.issue-agent.plist.template

check: lint test test-automation
