class_name TestTracks
## The two ideal boats computed in one go, for tests. The game computes the same IdealRun objects a
## few milliseconds per frame instead.


static func ideal_ghosts(pkg: LegPackage, boat: BoatProfile) -> Array[Ghost]:
	var out: Array[Ghost] = []
	for src in [RaceSim.WindSource.FORECAST, RaceSim.WindSource.ACTUAL]:
		var run := IdealRun.new(pkg, boat, src)
		while not run.done:
			run.step(1000.0)
		out.append(run.ghost)
	return out
