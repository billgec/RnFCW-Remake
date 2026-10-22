extends RefCounted
## Test bookkeeping. Collects everything that went wrong instead of stopping at the first
## one, so a single run tells the whole story.

var passed := 0
var failures: Array[String] = []


func ok(condition: bool, what: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(what)


func same(actual, expected, what: String) -> void:
	ok(actual == expected, "%s - got %s, wanted %s" % [what, actual, expected])


func near(actual: float, expected: float, what: String, tolerance := 0.01) -> void:
	ok(absf(actual - expected) <= tolerance, "%s - got %.3f, wanted %.3f" % [what, actual, expected])


func near_vector(actual: Vector2, expected: Vector2, what: String, tolerance := 0.01) -> void:
	ok(actual.distance_to(expected) <= tolerance, "%s - got %v, wanted %v" % [what, actual, expected])


## Prints the outcome and returns the exit code the run should end with.
func report(suite: String) -> int:
	if failures.is_empty():
		print("%s: %d checks passed" % [suite, passed])
		return 0
	print("%s: %d passed, %d FAILED" % [suite, passed, failures.size()])
	for failure in failures:
		print("  - %s" % failure)
	return 1
