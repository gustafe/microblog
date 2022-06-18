<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:atom="http://www.w3.org/2005/Atom">
	<xsl:output method="html" version="1.0" encoding="UTF-8" doctype-system="about:legacy-compat" indent="yes"/>
	<xsl:template match="/">
		<html lang="en">
		<head>
			<meta charset="utf-8" />
			<meta name="viewport" content="width=device-width, initial-scale=1.0" />
			<title><xsl:value-of select="/atom:feed/atom:title"/> RSS Preview</title>
		</head>
		<body>
			<header>
				<a href="/m">home</a>
			</header>
			<main>
				<header>
					<h1><xsl:value-of select="/atom:feed/atom:title"/> Feed, RSS Preview</h1>
					<p>You're looking at a styled version of my <a href="https://en.wikipedia.org/wiki/RSS">RSS feed</a>. With the right software, you can use this URL to get told when my website updates. <a href="https://feedly.com/">Feedly</a> is <em>my</em> personal preference (web, apps for Android and iOS) but there are <a href="https://en.wikipedia.org/wiki/Comparison_of_feed_aggregators">hundreds of alternatives</a>.</p>
					<p><code><xsl:value-of select="/atom:feed/atom:link/@href"/></code></p>
				</header>
				<xsl:for-each select="/atom:feed/atom:entry">
					<article>
						<h2>
							<a>
								<xsl:attribute name="href">
									<xsl:value-of select="atom:link/@href"/>
								</xsl:attribute>
								<xsl:value-of select="atom:title"/>
							</a>
						</h2>
						<p class="meta"><xsl:value-of select="atom:updated" /></p>
						<xsl:value-of select="atom:summary" disable-output-escaping="yes" />
					</article>
				</xsl:for-each>
			</main>
		</body>
		</html>
	</xsl:template>
</xsl:stylesheet>
