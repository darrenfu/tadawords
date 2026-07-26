.PHONY: generate format lint test test-automation test-release-preflight release-preflight check-changed check-pr check-rc check

TEAM_ID ?= 7R78Q4HP86

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
	python3 -m py_compile Scripts/verify-pawgoo-development-app.py
	python3 -m json.tool Config/release-candidate-policy.json >/dev/null

release-preflight:
	./Scripts/release-candidate-preflight.py \
		--archive "$(ARCHIVE)" \
		--exported-app "$(EXPORTED_APP)" \
		--expected-team "$(TEAM_ID)" \
		--manifest "$(or $(MANIFEST),.build/release-candidate-manifest.json)"

check-changed:
	python3 Scripts/delivery-checks.py \
		--mode changed \
		--base "$(or $(BASE_REF),origin/main)" \
		$(if $(TEST_FILTER),--swift-test-filter "$(TEST_FILTER)",)

check-pr:
	python3 Scripts/delivery-checks.py \
		--mode pr \
		--base "$(or $(BASE_REF),origin/main)"

check-rc:
	python3 Scripts/delivery-checks.py --mode rc

# Compatibility alias. A normal PR is not a release candidate.
check: check-pr
