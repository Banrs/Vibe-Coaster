//! Judging a ride.
//!
//! Two kinds of limit, and the difference between them is the whole design.
//!
//! **Comfort is pass or fail.** The rider force envelope does not scale with
//! the ride. A three-hundred-metre coaster gets the same handful of g as a
//! hundred-metre one, because the limit is the person in the seat. No
//! parameter, no technology and no ambition relaxes it.
//!
//! **Buildability is a cost.** Height, speed, length and support steel are
//! bounded by engineering, and engineering moves. So a record-breaker should
//! come back from this module *comfortable and expensive*, never rejected.
//!
//! The envelope checks are duration-scaled, which is subtler than it sounds. A
//! peak-only check asks "how much g did the rider ever see"; the standards ask
//! "how much g did the rider see *continuously for this long*". The quantity
//! that matters is therefore the largest value sustained across a window —
//! the maximum over all windows of the minimum within one — computed here for
//! every duration the envelope names.

use std::collections::VecDeque;

use vc_math::Scalar;

use crate::eval::Ride;
use crate::model::{Envelope, RideModel};

/// One limit, and how far the ride is over it.
///
/// `over` is in the quantity's own units and is negative when the ride is
/// inside the limit. Checks are always produced, passing or failing, so that
/// the residual vector the solve sees is a fixed length.
#[derive(Clone, Debug)]
pub struct Check<T: Scalar> {
    /// What was checked, for the report.
    pub name: String,
    /// Amount over the limit. At or below zero is a pass.
    pub over: T,
}

/// What a ride turned out to be.
#[derive(Clone, Debug)]
pub struct Analysis<T: Scalar> {
    /// Every limit, passing or failing.
    pub checks: Vec<Check<T>>,
    /// Measurements reported but not enforced, because a check already in
    /// `checks` provably dominates them. The solve never sees these: even a
    /// penalty that is zero at the answer reshapes the path to it.
    pub advisories: Vec<Check<T>>,
    /// Closest the heartline comes to the ground, metres.
    pub min_clearance: T,
    /// Fastest point, m/s.
    pub top_speed: T,
    /// Track length over ride time, m/s. The pacing number: a ride that touches
    /// its top speed once and crawls the rest is slow, and only this notices.
    pub average_speed: T,
    /// Highest point above the station, metres.
    pub highest: T,
    /// Track length, metres. The first term of what it costs to build.
    pub track_length: T,
    /// Integral of height above ground along the track, metre-metres. A proxy
    /// for support steel: a ride hugging the terrain is cheap, one on stilts
    /// is not.
    pub support_metres: T,
}

impl<T: Scalar> Analysis<T> {
    /// Penalty residuals for the solve: zero where a limit is met, the amount
    /// over where it is not.
    pub fn penalties(&self) -> Vec<T> {
        self.checks.iter().map(|c| c.over.max(T::ZERO)).collect()
    }

    /// Only the limits actually broken, worst first.
    pub fn failures(&self) -> Vec<&Check<T>> {
        let mut failed: Vec<_> = self
            .checks
            .iter()
            .filter(|c| c.over.to_f64() > 0.0)
            .collect();
        failed.sort_by(|a, b| b.over.to_f64().total_cmp(&a.over.to_f64()));
        failed
    }
}

/// Measures a ride against its limits and its site.
pub fn analyse<T: Scalar>(model: &RideModel, ride: &Ride<T>) -> Analysis<T> {
    let times: Vec<T> = ride.samples.iter().map(|s| s.time).collect();
    let mut checks = Vec::new();

    let normal: Vec<T> = ride.samples.iter().map(|s| s.normal_g).collect();
    let lateral: Vec<T> = ride.samples.iter().map(|s| s.lateral_g).collect();
    let longitudinal: Vec<T> = ride.samples.iter().map(|s| s.longitudinal_g).collect();

    envelope_checks(
        &mut checks,
        "normal +g",
        &times,
        &normal,
        &model.limits.normal_positive,
        false,
    );
    envelope_checks(
        &mut checks,
        "normal -g",
        &times,
        &normal,
        &model.limits.normal_negative,
        true,
    );
    envelope_checks(
        &mut checks,
        "lateral +g",
        &times,
        &lateral,
        &model.limits.lateral,
        false,
    );
    envelope_checks(
        &mut checks,
        "lateral -g",
        &times,
        &lateral,
        &model.limits.lateral,
        true,
    );
    envelope_checks(
        &mut checks,
        "longitudinal +g",
        &times,
        &longitudinal,
        &model.limits.longitudinal,
        false,
    );
    envelope_checks(
        &mut checks,
        "longitudinal -g",
        &times,
        &longitudinal,
        &model.limits.longitudinal,
        true,
    );

    // Jerk, taken across all three axes: the rider feels the rate of change of
    // the whole force, not of one component. Two checks, because the figure
    // has two meanings and conflating them mis-judged this ride once.
    //
    // The *design* check is the instantaneous slope of the authored profile
    // against `limits.jerk` — Rohde's "5 g/s or max. 10 g/s in the design
    // phase" guidance is about the profile as drawn, and it is also the
    // constraint the solve feels, which keeps transition shape priced in.
    //
    // The *proving* check measures what the standard measures. F2291 defines
    // onset rate as a straight-line slope across a window of the order of a
    // tenth of a second on a low-passed signal, never a per-step derivative —
    // Rohde's worked loop entry has a clothoid join with mathematically
    // infinite instantaneous jerk and passes, "the jerk must act over a
    // certain period of time". Its 15 g/s is the standard's own figure, which
    // is why it sits here as a constant rather than in the rulebook data.
    let mut design_jerk = T::ZERO;
    for w in ride.samples.windows(2) {
        let dt = w[1].time - w[0].time;
        if dt.to_f64() <= 0.0 {
            continue;
        }
        design_jerk = design_jerk.max(felt_change(&w[1], &w[0]) / dt);
    }
    checks.push(Check {
        name: format!("jerk, authored (design {:.0} g/s)", model.limits.jerk),
        over: design_jerk - T::from_f64(model.limits.jerk),
    });

    // Advisory rather than enforced, and provably safe to leave so: an
    // event-to-event mean slope is a mean of instantaneous slopes, so it can
    // never exceed 15 without the design check above firing harder — as long
    // as the design limit stays at or below the proving figure.
    const JERK_PROVING_LIMIT: f64 = 15.0;
    let proving_jerk = [&normal, &lateral, &longitudinal]
        .into_iter()
        .fold(T::ZERO, |m, axis| m.max(onset_rate(&times, axis)));
    let advisories = vec![Check {
        name: format!("jerk, proving window (limit {JERK_PROVING_LIMIT:.0} g/s)"),
        over: proving_jerk - T::from_f64(JERK_PROVING_LIMIT),
    }];

    let worst_roll = ride
        .samples
        .iter()
        .fold(T::ZERO, |m, s| m.max(s.roll_rate.abs()));
    checks.push(Check {
        name: format!("roll rate (limit {:.0} deg/s)", model.limits.roll_rate),
        over: worst_roll - T::from_f64(model.limits.roll_rate),
    });

    let min_clearance = ride
        .samples
        .iter()
        .fold(T::from_f64(f64::MAX), |m, s| m.min(s.clearance));
    checks.push(Check {
        name: format!("ground clearance (min {:.1} m)", model.site.min_clearance),
        over: T::from_f64(model.site.min_clearance) - min_clearance,
    });

    let (low, high) = ride.samples.iter().fold(
        (T::from_f64(f64::MAX), T::from_f64(f64::MIN)),
        |(lo, hi), s| (lo.min(s.position.z), hi.max(s.position.z)),
    );
    checks.push(Check {
        name: format!(
            "elevation span (limit {:.0} m)",
            model.site.max_elevation_span
        ),
        over: high - low - T::from_f64(model.site.max_elevation_span),
    });

    let top_speed = ride.samples.iter().fold(T::ZERO, |m, s| m.max(s.speed));
    if let Some(limit) = model.vehicle.wheel_speed_limit {
        // A buildability limit, not a comfort one: running gear that overheats
        // is a cost and a cycle-rate restriction. Reported, and left for the
        // human to price.
        checks.push(Check {
            name: format!("wheel speed (limit {limit:.0} m/s)"),
            over: top_speed - T::from_f64(limit),
        });
    }

    // Support steel proxy: how much height above ground the track carries, and
    // for how far.
    let mut support = T::ZERO;
    for w in ride.samples.windows(2) {
        let ds = w[1].s - w[0].s;
        support +=
            (w[0].clearance.max(T::ZERO) + w[1].clearance.max(T::ZERO)) * ds * T::from_f64(0.5);
    }

    Analysis {
        checks,
        advisories,
        min_clearance,
        top_speed,
        average_speed: ride.length / ride.duration,
        highest: ride.elements.iter().fold(T::ZERO, |m, e| m.max(e.apex)),
        track_length: ride.length,
        support_metres: support,
    }
}

/// Magnitude of the change in felt force between two samples, g, across all
/// three axes.
fn felt_change<T: Scalar>(b: &crate::eval::Sample<T>, a: &crate::eval::Sample<T>) -> T {
    ((b.normal_g - a.normal_g).squared()
        + (b.lateral_g - a.lateral_g).squared()
        + (b.longitudinal_g - a.longitudinal_g).squared())
    .sqrt()
}

/// Onset rate as the standard measures it: the mean slope of each monotone
/// transition, taken between its endpoints, maximised over transitions.
///
/// F2291 computes onset as a straight-line slope between two events on a
/// low-passed signal, never as a pointwise derivative. Events here are the
/// signal's turning points, found with the same ±0.1 g band the standard's
/// slice method uses for durations, which also keeps flat-channel noise from
/// splitting one transition into many short steep-looking ones.
fn onset_rate<T: Scalar>(times: &[T], values: &[T]) -> T {
    /// The standard's slice level, g.
    const BAND: f64 = 0.1;
    let mut worst = T::ZERO;
    let mut start = 0usize;
    let mut extreme = 0usize;
    let mut rising: Option<bool> = None;
    for i in 1..values.len() {
        let against = |up: bool| {
            if up {
                values[extreme] - values[i]
            } else {
                values[i] - values[extreme]
            }
        };
        match rising {
            None => {
                if (values[i] - values[start]).abs().to_f64() > BAND {
                    rising = Some(values[i].to_f64() > values[start].to_f64());
                    extreme = i;
                }
            }
            Some(up) => {
                let advanced = if up {
                    values[i].to_f64() > values[extreme].to_f64()
                } else {
                    values[i].to_f64() < values[extreme].to_f64()
                };
                if advanced {
                    extreme = i;
                } else if against(up).to_f64() > BAND {
                    // The transition ended at its extreme; score it and start
                    // the next one there.
                    let span = times[extreme] - times[start];
                    if span.to_f64() > 0.0 {
                        worst = worst.max((values[extreme] - values[start]).abs() / span);
                    }
                    start = extreme;
                    rising = Some(!up);
                    extreme = i;
                }
            }
        }
    }
    let last = values.len() - 1;
    let span = times[last] - times[start];
    if rising.is_some() && span.to_f64() > 0.0 {
        worst = worst.max((values[last] - values[start]).abs() / span);
    }
    worst
}

/// Adds one check per duration the envelope names.
fn envelope_checks<T: Scalar>(
    checks: &mut Vec<Check<T>>,
    axis: &str,
    times: &[T],
    values: &[T],
    envelope: &Envelope,
    negate: bool,
) {
    for duration in envelope.durations() {
        let limit = envelope.at(duration);
        let held = max_sustained(times, values, T::from_f64(duration), negate);
        // A ride shorter than the window cannot violate it.
        let over = held.map_or(-T::ONE, |h| h - T::from_f64(limit));
        checks.push(Check {
            name: format!("{axis} over {duration:.1} s (limit {limit:.1} g)"),
            over,
        });
    }
}

/// The largest value held continuously for at least `window` seconds.
///
/// Sliding-window minimum by monotonic deque, then the maximum of those
/// minima. The deque keeps this linear; the obvious nested loop is quadratic,
/// and at ten thousand samples times seven durations times six axes that is
/// the difference between a solve step and a coffee break.
///
/// With `negate`, measures the same thing for the mirrored signal, which is
/// how a negative-g limit is checked without a second code path.
fn max_sustained<T: Scalar>(times: &[T], values: &[T], window: T, negate: bool) -> Option<T> {
    let at = |i: usize| if negate { -values[i] } else { values[i] };
    let mut increasing: VecDeque<usize> = VecDeque::new();
    let mut start = 0usize;
    let mut best: Option<T> = None;

    for end in 0..values.len() {
        while increasing.back().is_some_and(|&b| at(b) >= at(end)) {
            increasing.pop_back();
        }
        increasing.push_back(end);

        // Advance the window's start as far as it can go while still spanning
        // the full duration.
        while start < end && times[end] - times[start + 1] >= window {
            start += 1;
        }
        while increasing.front().is_some_and(|&f| f < start) {
            increasing.pop_front();
        }

        if times[end] - times[start] >= window {
            let held = at(increasing[0]);
            best = Some(best.map_or(held, |b: T| b.max(held)));
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::eval::evaluate;
    use crate::preset;

    fn ramp(values: &[f64], step: f64) -> (Vec<f64>, Vec<f64>) {
        let times = (0..values.len()).map(|i| i as f64 * step).collect();
        (times, values.to_vec())
    }

    #[test]
    fn sustained_is_not_peak() {
        // A one-sample spike to 5 g is not five g sustained for a second.
        let (t, v) = ramp(
            &[1.0, 1.0, 5.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
            0.2,
        );
        assert!((max_sustained(&t, &v, 1.0, false).unwrap() - 1.0).abs() < 1e-12);
        // Held across the whole window, it is.
        let (t2, v2) = ramp(&[5.0; 11], 0.2);
        assert!((max_sustained(&t2, &v2, 1.0, false).unwrap() - 5.0).abs() < 1e-12);
    }

    #[test]
    fn sustained_finds_the_best_window_not_the_first() {
        let (t, v) = ramp(&[1.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 1.0], 0.25);
        let held = max_sustained(&t, &v, 1.0, false).unwrap();
        assert!((held - 3.0).abs() < 1e-12, "{held}");
    }

    #[test]
    fn negation_checks_the_other_direction_with_the_same_code() {
        let (t, v) = ramp(&[-1.2; 10], 0.2);
        assert!((max_sustained(&t, &v, 1.0, true).unwrap() - 1.2).abs() < 1e-12);
        assert!(max_sustained(&t, &v, 1.0, false).unwrap() < 0.0);
    }

    #[test]
    fn a_window_longer_than_the_ride_cannot_be_violated() {
        let (t, v) = ramp(&[9.0, 9.0, 9.0], 0.1);
        assert!(max_sustained(&t, &v, 30.0, false).is_none());
    }

    #[test]
    fn the_preset_produces_a_full_set_of_checks() {
        let model = preset::falcon_class();
        let ride = evaluate(&model, &model.spec.free_parameters());
        let a = analyse(&model, &ride);
        assert!(!a.checks.is_empty());
        // Every check must be finite, or the solve gets a poisoned residual.
        assert!(
            a.checks.iter().all(|c| c.over.is_finite()),
            "non-finite check: {:?}",
            a.checks
                .iter()
                .find(|c| !c.over.is_finite())
                .map(|c| &c.name)
        );
        assert_eq!(a.penalties().len(), a.checks.len());
        assert!(a.penalties().iter().all(|p| *p >= 0.0));
        assert!(a.track_length > 2500.0);
    }

    #[test]
    fn penalties_are_zero_where_limits_are_met() {
        let model = preset::falcon_class();
        let ride = evaluate(&model, &model.spec.free_parameters());
        let a = analyse(&model, &ride);
        for (check, penalty) in a.checks.iter().zip(a.penalties()) {
            if check.over <= 0.0 {
                assert!(
                    penalty.abs() < 1e-15,
                    "{} penalised at {penalty}",
                    check.name
                );
            }
        }
    }
}
