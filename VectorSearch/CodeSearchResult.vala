namespace VectorSearch
{
	public class CodeSearchResult : Object
	{
		public CodeElement element { get; set; default = new CodeElement(); }
		public float similarity_score { get; set; default = 0.0f; }
		public int rank { get; set; default = 0; }
		public string relevant_snippet { get; set; default = ""; }
		
		public CodeSearchResult()
		{
		}
	}
}

