resource "azurerm_resource_group" "app_insight_rg" {
  name = "${var.app_insights_rg}"
  location = "west us 2"
}

resource "azurerm_application_insights" "app_insights" {
  name = "app_insights"
  location = "${azurerm_resource_group.app_insight_rg.location}"
  resource_group_name = "${azurerm_resource_group.app_insight_rg.name}"
  application_type = "web"
}

output "instrumentation_key" {
    value = "${azurerm_application_insights.app_insights.app_insights.instrumentation_key}"
}

output "app_id" {
    value = "${azurerm_application_insights.app_insights.app_id}"
}