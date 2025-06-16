import 'package:dialog_flowtter/dialog_flowtter.dart';

class DialogflowService {
  final DialogFlowtter dialogFlowtter;

  DialogflowService(this.dialogFlowtter);

  Future<String> getDialogflowResponse(String query, {String? userId}) async {
    try {
      DetectIntentResponse response = await dialogFlowtter.detectIntent(
        queryInput: QueryInput(text: TextInput(text: query)),
        queryParams: QueryParameters(
          payload: {
            "userId": userId ?? "", // Send userId inside payload
          },
        ),
      );

      var queryResult = response.queryResult;
      if (queryResult == null || queryResult.fulfillmentMessages == null ||
          queryResult.fulfillmentMessages!.isEmpty) {
        return "Sorry, I didn't understand that.";
      }

      String responseText = queryResult.fulfillmentMessages![0].text?.text !=
          null
          ? queryResult.fulfillmentMessages![0].text!.text!.join(" ")
          : "Sorry, I didn't understand that.";

      print("🔍 Extracted parameters: ${queryResult.parameters}");

      var parameters = queryResult.parameters ?? {};
      String intentName = queryResult.intent?.displayName ?? "";

      print("✅ Detected intent: $intentName");

      return responseText;
    } catch (e) {
      print("❌ Error in Dialogflow response: $e");
      return "An error occurred while processing your request.";
    }
  }
}
