## A minimal test harness.
##
## GDScript has no compile-time exhaustiveness checking: an enum misspelled or a
## variant field accessed wrongly becomes a runtime null rather than a build
## failure. In a fixed-step combat simulation that is a bad trade, because the
## whole point of splitting the simulation from the engine is that it can be
## verified without running the game. So the tests are not optional polish here
## - they are what stands in for the type system, and they run headless with no
## window.
##
## Deliberately tiny and dependency-free. GDD 13.4 wants automated coverage of
## attack windows, guard break, stagger immunity and seeded routes; that is a
## lot of assertions, and an assert library would only get in the way.
class_name TestHarness
extends RefCounted

var passed := 0
var failed := 0
var failures: Array[String] = []
var _suite := ""
var _assertions := 0

## Suites that were entered. A suite whose file failed to parse leaves this
## short, which is how a wholly broken test file is told apart from a genuinely
## clean run. Without this, a compile error makes the runner exit zero and CI
## reports green on nothing at all.
var suites_run := 0

## The suite count the runner expects. Set by the runner before it starts.
var suites_expected := 0


func suite(name: String) -> void:
	_suite = name
	suites_run += 1
	print("\n  %s" % name)


func ok(condition: bool, message: String) -> bool:
	_assertions += 1
	if condition:
		passed += 1
		return true
	failed += 1
	var line := "%s: %s" % [_suite, message]
	failures.append(line)
	print("    FAIL  %s" % message)
	return false


func eq_int(actual: int, expected: int, message: String) -> bool:
	return ok(actual == expected, "%s (expected %d, got %d)" % [message, expected, actual])


func eq_float(actual: float, expected: float, message: String, epsilon := 0.0001) -> bool:
	return ok(
		absf(actual - expected) <= epsilon,
		"%s (expected %f, got %f)" % [message, expected, actual]
	)


func eq_bool(actual: bool, expected: bool, message: String) -> bool:
	return ok(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func eq_string(actual: String, expected: String, message: String) -> bool:
	return ok(actual == expected, "%s\n            expected: %s\n            actual:   %s"
		% [message, expected, actual])


func between(actual: int, low: int, high: int, message: String) -> bool:
	return ok(
		actual >= low and actual <= high,
		"%s (expected %d..%d, got %d)" % [message, low, high, actual]
	)


func summary() -> void:
	print("\n%s" % ("-".repeat(60)))
	if _assertions == 0:
		print("  NO ASSERTIONS RAN")
	elif failed == 0:
		print("  %d assertions passed across %d suites" % [passed, suites_run])
	else:
		print("  %d passed, %d FAILED of %d assertions" % [passed, failed, _assertions])
		for f in failures:
			print("    - %s" % f)
	print("%s" % ("-".repeat(60)))


## Non-zero on a real failure, and also on the case that matters most for a
## test runner: no assertions at all, because a suite file did not compile.
func exit_code() -> int:
	if _assertions == 0:
		return 2
	if suites_expected > 0 and suites_run < suites_expected:
		print("  only %d of %d suites ran" % [suites_run, suites_expected])
		return 3
	return 0 if failed == 0 else 1