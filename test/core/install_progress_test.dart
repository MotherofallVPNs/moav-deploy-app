import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/install_progress.dart';
import 'package:moav_deploy/core/install_script.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// Progress follows the four deploy phases weighted by their typical
/// duration and keeps creeping inside a long step; 100% is the exit marker.
void main() {
  const total = InstallScript.totalSteps;

  double at(int step, Duration elapsed) =>
      InstallProgress.estimate(step: step, totalSteps: total, elapsed: elapsed);

  test('spans cover the bar in order and stop short of 100%', () {
    expect(InstallProgress.spans.length, total);
    var prevEnd = 0.0;
    for (final (start, end, typical) in InstallProgress.spans) {
      expect(start, prevEnd);
      expect(end, greaterThan(start));
      expect(typical, greaterThan(Duration.zero));
      prevEnd = end;
    }
    expect(prevEnd, lessThan(1.0));
  });

  test('the bootstrap step owns most of the bar', () {
    final (start, end, typical) = InstallProgress.spanFor(3, total);
    expect(end - start, greaterThan(0.5));
    expect(typical, greaterThanOrEqualTo(const Duration(minutes: 5)));
  });

  test('a step starts at its floor and eases toward its end over time', () {
    final (start, end, typical) = InstallProgress.spanFor(3, total);
    expect(at(3, Duration.zero), start);
    final half = at(3, typical ~/ 2);
    final one = at(3, typical);
    final two = at(3, typical * 2);
    final ten = at(3, typical * 10);
    expect(half, greaterThan(start));
    expect(one, greaterThan(half));
    expect(two, greaterThan(one));
    expect(ten, greaterThan(two));
    // About 80% of the span at the typical duration, never the end.
    expect((one - start) / (end - start), closeTo(0.8, 0.02));
    expect(ten, lessThan(end));
  });

  test('no step pins at two thirds; step 2 ends well before bootstrap', () {
    expect(at(2, const Duration(hours: 1)), lessThan(0.25));
    expect(at(3, const Duration(minutes: 7)), greaterThan(0.6));
    expect(at(4, Duration.zero), greaterThanOrEqualTo(0.9));
    expect(at(4, const Duration(hours: 1)), lessThan(1.0));
  });

  test('a job with another step count gets even spans', () {
    expect(InstallProgress.floorOf(1, 3), 0);
    expect(InstallProgress.floorOf(2, 3), closeTo(0.33, 0.01));
    expect(
      InstallProgress.estimate(step: 3, totalSteps: 3, elapsed: const Duration(days: 1)),
      lessThan(1.0),
    );
  });

  group('parseInstallStatus step fields', () {
    test('reads the step and the denominator from the marker', () {
      final s = SshMoavController.parseInstallStatus(
        'ALIVE\n__LOG__\n[moav-deploy] step 1/4: Preflight\n'
        '[moav-deploy] step 3/4: Bootstrap MoaV\n#1 [internal] load build definition\n',
      );
      expect(s.step, 3);
      expect(s.totalSteps, 4);
      expect(s.progress, closeTo(0.75, 1e-9));
      expect(s.message, 'Bootstrap MoaV');
    });

    test('an older three-step log keeps its own denominator', () {
      final s = SshMoavController.parseInstallStatus(
        'ALIVE\n__LOG__\n[moav-deploy] step 2/3: Run MoaV installer\n',
      );
      expect(s.step, 2);
      expect(s.totalSteps, 3);
      expect(s.progress, closeTo(2 / 3, 1e-9));
    });

    test('no step yet means no step fields', () {
      final s = SshMoavController.parseInstallStatus('ALIVE\n__LOG__\nhello\n');
      expect(s.step, isNull);
      expect(s.totalSteps, isNull);
      expect(s.progress, isNull);
    });
  });
}
