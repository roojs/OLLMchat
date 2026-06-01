/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OllamaWeb.Search
{
	public enum Category {
		NONE,
		EMBEDDING,
		VISION,
		TOOLS,
		THINKING
	}

	public enum Sort {
		POPULAR,
		NEWEST
	}

	public errordomain Error {
		RATE_LIMITED,
		NOT_FOUND,
		NETWORK,
		PARSE
	}
}
