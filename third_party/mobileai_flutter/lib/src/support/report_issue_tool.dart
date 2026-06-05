import '../core/types.dart';
import 'types.dart';

ToolDefinition createReportIssueTool({
  required Future<ReportedIssue> Function(String description) onReport,
}) {
  return ToolDefinition(
    name: 'report_issue',
    description: 'Report a product or support issue to the backend.',
    parameters: {
      'description': ToolParam(
        type: 'string',
        description: 'Customer-facing issue description',
      ),
    },
    handler: (args) async {
      final description = '${args['description'] ?? ''}'.trim();
      final result = await onReport(description);
      return 'ISSUE_REPORTED:${result.id}:${result.customerStatus}:${result.complaintSummary}';
    },
  );
}
