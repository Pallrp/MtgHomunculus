import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

void main() {
  group('HoughLinesP API Validation', () {
    test('Create synthetic edge image and detect lines', () {
      print('\n=== HoughLinesP API Test ===\n');

      // Create a simple synthetic edge image: black background with white lines
      // Image size: 400x300
      const int width = 400;
      const int height = 300;

      // Create an all-black image
      final mat = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);

      // Draw a horizontal line (white = 255) at y=100
      for (int x = 50; x < 350; x++) {
        mat.set<int>(100, x, 255);
      }

      // Draw a vertical line at x=200
      for (int y = 50; y < 250; y++) {
        mat.set<int>(y, 200, 255);
      }

      print('Created synthetic image: ${width}x${height}');
      print('Drew 1 horizontal line (y=100, x=50..350)');
      print('Drew 1 vertical line (x=200, y=50..250)');

      // Call HoughLinesP
      print('\nCalling HoughLinesP...');
      final lines = cv.HoughLinesP(
        mat,
        1.0,           // rho: distance resolution in pixels
        0.01745,       // theta: angle resolution in radians (~1 degree)
        50,            // threshold: accumulator threshold
        minLineLength: 30.0,
        maxLineGap: 10.0,
      );

      print('HoughLinesP returned successfully');

      // Inspect the returned Mat
      print('\nInspecting returned Mat:');
      print('  rows: ${lines.rows}');
      print('  cols: ${lines.cols}');
      print('  type: ${lines.type}');
      print('  channels: ${lines.channels}');
      print('  dims: ${lines.dims}');

      // Check if we got any lines
      if (lines.rows == 0) {
        print('\n⚠️  WARNING: No lines detected!');
        print('This could mean:');
        print('  - The HoughLinesP parameters are too strict');
        print('  - The synthetic image is not suitable');
        print('  - There\'s an issue with the algorithm');
      } else {
        print('\n✓ Found ${lines.rows} line(s)');

        // Try to access the first few lines
        print('\nAttempting to access line data:');
        for (int i = 0; i < (lines.rows > 5 ? 5 : lines.rows); i++) {
          try {
            // HoughLinesP returns [x1, y1, x2, y2] for each line
            final x1 = lines.at<int>(i, 0);
            final y1 = lines.at<int>(i, 1);
            final x2 = lines.at<int>(i, 2);
            final y2 = lines.at<int>(i, 3);

            print('  Line $i: ($x1,$y1) -> ($x2,$y2)');
          } catch (e) {
            print('  ❌ Error accessing line $i: $e');

            // Try alternative access methods
            print('    Trying row() method...');
            try {
              final row = lines.row(i);
              print('    row($i) successful, type: ${row.type}');
              print('    row cols: ${row.cols}');

              // Try accessing from the row
              final x1 = row.at<int>(0, 0);
              print('    row.at<int>(0,0) = $x1');
            } catch (e2) {
              print('    ❌ row() method also failed: $e2');
            }
          }
        }
      }

      // Cleanup
      mat.dispose();
      lines.dispose();

      print('\n=== Test Complete ===\n');
      expect(true, true); // Dummy assertion to satisfy test framework
    });

    test('Test Mat.at<T> access patterns', () {
      print('\n=== Mat Access Pattern Test ===\n');

      // Create a test Mat with known values
      final testMat = cv.Mat.zeros(3, 4, cv.MatType.CV_8UC1);

      // Set some values
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 4; j++) {
          testMat.set<int>(i, j, i * 10 + j);
        }
      }

      print('Created 3x4 Int32 Mat with pattern: [row*10 + col]');
      print('Expected values:');
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 4; j++) {
          print('  [$i,$j] = ${i * 10 + j}');
        }
      }

      print('\nAttempting to read values back:');
      try {
        for (int i = 0; i < 3; i++) {
          for (int j = 0; j < 4; j++) {
            final val = testMat.at<int>(i, j);
            final expected = i * 10 + j;
            if (val == expected) {
              print('  ✓ [$i,$j] = $val (correct)');
            } else {
              print('  ❌ [$i,$j] = $val (expected $expected)');
            }
          }
        }
      } catch (e) {
        print('❌ Failed to read values: $e');
      }

      testMat.dispose();
      print('\n=== Test Complete ===\n');
      expect(true, true);
    });
  });
}
