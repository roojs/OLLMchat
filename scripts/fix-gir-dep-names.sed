# Vala shortens nested-namespace names in dependent GIR files. Apply longer
# replacements first so partial matches (e.g. BaseTool inside BaseToolConfig) do
# not corrupt type names.
s/OLLMchat\.BaseToolConfigClass/OLLMchat.SettingsBaseToolConfigClass/g
s/OLLMchat\.BaseToolConfig/OLLMchat.SettingsBaseToolConfig/g
s/OLLMchat\.BaseToolClass/OLLMchat.ToolBaseToolClass/g
s/OLLMchat\.BaseTool/OLLMchat.ToolBaseTool/g
s/OLLMchat\.RequestBaseClass/OLLMchat.ToolRequestBaseClass/g
s/OLLMchat\.RequestBase/OLLMchat.ToolRequestBase/g
s/OLLMchat\.TemplateClass/OLLMchat.PromptTemplateClass/g
s/OLLMchat\.Template/OLLMchat.PromptTemplate/g
s/OLLMchat\.FactoryClass/OLLMchat.AgentFactoryClass/g
s/OLLMchat\.Factory/OLLMchat.AgentFactory/g
s/OLLMchat\.BaseClass/OLLMchat.AgentBaseClass/g
s/OLLMchat\.Base/OLLMchat.AgentBase/g
s/OLLMchat\.PermissionResponse/OLLMchat.ChatPermissionPermissionResponse/g
s/OLLMchat\.ProviderClass/OLLMchat.ChatPermissionProviderClass/g
s/OLLMchat\.Provider/OLLMchat.ChatPermissionProvider/g
s/OLLMchat\.SessionBase/OLLMchat.HistorySessionBase/g
s/OLLMchat\.Manager/OLLMchat.HistoryManager/g
s/OLLMchat\.ModelUsage/OLLMchat.SettingsModelUsage/g
s/OLLMchat\.Config2/OLLMchat.SettingsConfig2/g
s/OLLMchat\.ToolCall/OLLMchat.ResponseToolCall/g
s/OLLMchat\.WrapInterface/OLLMchat.ToolWrapInterface/g
s/type name="OLLMchat\.Chat"/type name="OLLMchat.ResponseChat"/g
