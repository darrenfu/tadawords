.PHONY: generate format lint test test-automation test-release-preflight release-preflight check

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

test-release-preflight:
	python3 -m unittest discover -s Automation/release-preflight/tests -v
	python3 -m py_compile Scripts/release-candidate-preflight.py
	python3 -m json.tool Config/release-candidate-policy.json >/dev/null

release-preflight:
	./Scripts/release-candidate-preflight.py \
		--archive "$(ARCHIVE)" \
		--exported-app "$(EXPORTED_APP)" \
		--expected-team "$(TEAM_ID)" \
		--manifest "$(or $(MANIFEST),.build/release-candidate-manifest.json)"

check: lint test test-automation test-release-preflight
