import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/import/otp_import_service.dart';
import '../../platform/camera/camera_qr_capture_service.dart';
import '../../platform/clipboard/clipboard_import_reader.dart';
import '../../platform/files/image_import_picker.dart';
import '../../platform/screenshot/screen_capture_service.dart';

/// Shared import parser used by all future QR input surfaces.
final otpImportServiceProvider = Provider<OtpImportService>(
  (ref) => const OtpImportService(),
);

/// Device file picker isolated behind a testable platform boundary.
final imageImportPickerProvider = Provider<ImageImportPicker>(
  (ref) => FileSelectorImageImportPicker(),
);

/// Device clipboard reader isolated behind a testable platform boundary.
final clipboardImportReaderProvider = Provider<ClipboardImportReader>(
  (ref) => const PlatformClipboardImportReader(),
);

/// Interactive region screenshot isolated behind a testable platform boundary.
final screenCaptureServiceProvider = Provider<ScreenCaptureService>(
  (ref) => const PlatformScreenCaptureService(),
);

/// Desktop camera adapter isolated so scanner widgets can use deterministic fakes.
final cameraQrCaptureServiceProvider = Provider<CameraQrCaptureService>(
  (ref) => const DesktopCameraQrCaptureService(),
);
