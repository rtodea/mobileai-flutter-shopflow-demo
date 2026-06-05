import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/logger.dart';

/// AgentErrorBoundary — Catches and displays errors in the AI agent subtree.
///
/// Wraps the agent widget tree to catch Flutter errors and display
/// a user-friendly error UI instead of crashing the app.
class AgentErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace? stackTrace)? errorBuilder;
  final void Function(Object error, StackTrace? stackTrace)? onError;

  const AgentErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onError,
  });

  @override
  State<AgentErrorBoundary> createState() => _AgentErrorBoundaryState();
}

class _AgentErrorBoundaryState extends State<AgentErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    _installErrorHandler();
  }

  @override
  void dispose() {
    _removeErrorHandler();
    super.dispose();
  }

  FlutterExceptionHandler? _originalErrorHandler;

  void _installErrorHandler() {
    _originalErrorHandler = FlutterError.onError;

    FlutterError.onError = (details) {
      // Only handle errors in this subtree
      if (_isInSubtree(details.exception)) {
        _handleError(details.exception, details.stack);
      } else {
        _originalErrorHandler?.call(details);
      }
    };
  }

  void _removeErrorHandler() {
    if (_originalErrorHandler != null) {
      FlutterError.onError = _originalErrorHandler;
    }
  }

  bool _isInSubtree(Object error) {
    // Check if the error is related to the agent
    return _error != null;
  }

  void _handleError(Object error, StackTrace? stack) {
    Logger.error('AgentErrorBoundary caught error: $error');
    widget.onError?.call(error, stack);

    if (mounted) {
      setState(() {
        _error = error;
        _stackTrace = stack;
      });
    }
  }

  void _resetError() {
    if (mounted) {
      setState(() {
        _error = null;
        _stackTrace = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(_error!, _stackTrace) ??
          _DefaultErrorWidget(
            error: _error!,
            stackTrace: _stackTrace,
            onRetry: _resetError,
          );
    }

    return ErrorBoundary(
      onError: _handleError,
      child: widget.child,
    );
  }
}

/// Internal error boundary widget that catches errors in its child subtree.
class ErrorBoundary extends SingleChildRenderObjectWidget {
  final void Function(Object error, StackTrace? stack) onError;

  const ErrorBoundary({
    super.key,
    required this.onError,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _ErrorBoundaryRenderObject(onError);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _ErrorBoundaryRenderObject).onError = onError;
  }
}

class _ErrorBoundaryRenderObject extends RenderProxyBox {
  void Function(Object error, StackTrace? stack) onError;

  _ErrorBoundaryRenderObject(this.onError);

  @override
  void performLayout() {
    try {
      super.performLayout();
    } catch (e, stack) {
      onError(e, stack);
    }
  }
}

/// Default error widget displayed when an error is caught.
class _DefaultErrorWidget extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;

  const _DefaultErrorWidget({
    required this.error,
    this.stackTrace,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zone-specific error boundary for isolating agent errors.
class AgentZoneErrorBoundary extends StatefulWidget {
  final String zoneId;
  final Widget child;

  const AgentZoneErrorBoundary({
    super.key,
    required this.zoneId,
    required this.child,
  });

  @override
  State<AgentZoneErrorBoundary> createState() => _AgentZoneErrorBoundaryState();
}

class _AgentZoneErrorBoundaryState extends State<AgentZoneErrorBoundary> {
  Object? _error;

  void _handleError(Object error, StackTrace? stack) {
    Logger.error('Zone ${widget.zoneId} error: $error');
    if (mounted) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            const SizedBox(height: 4),
            Text(
              'Zone unavailable',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    return ErrorBoundary(
      onError: _handleError,
      child: widget.child,
    );
  }
}
