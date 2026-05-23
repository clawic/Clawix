using Markdig;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;

namespace Clawix.App.Views;

public sealed partial class MarkdownDocumentView : UserControl
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    public MarkdownDocumentView() { InitializeComponent(); }

    public void RenderMarkdown(string md)
    {
        Body.Blocks.Clear();
        var document = Markdown.Parse(md ?? string.Empty, Pipeline);
        foreach (var block in document)
            AddBlock(block, 0);

        if (Body.Blocks.Count == 0)
            Body.Blocks.Add(CreateParagraph());
    }

    private void AddBlock(Block block, int depth)
    {
        switch (block)
        {
            case HeadingBlock heading:
                AddHeading(heading);
                break;
            case ParagraphBlock paragraph:
                AddParagraphBlock(paragraph, depth);
                break;
            case ListBlock list:
                AddList(list, depth);
                break;
            case QuoteBlock quote:
                AddQuote(quote, depth);
                break;
            case CodeBlock code:
                AddCode(code, depth);
                break;
            case ThematicBreakBlock:
                var rule = CreateParagraph(depth);
                rule.Inlines.Add(new Run { Text = "---" });
                Body.Blocks.Add(rule);
                break;
        }
    }

    private void AddHeading(HeadingBlock heading)
    {
        var paragraph = CreateParagraph();
        paragraph.FontWeight = FontWeights.SemiBold;
        paragraph.FontSize = heading.Level switch
        {
            1 => 24,
            2 => 20,
            3 => 17,
            _ => 15
        };
        AddInlines(paragraph.Inlines, heading.Inline);
        Body.Blocks.Add(paragraph);
    }

    private void AddParagraphBlock(ParagraphBlock paragraphBlock, int depth)
    {
        var paragraph = CreateParagraph(depth);
        AddInlines(paragraph.Inlines, paragraphBlock.Inline);
        Body.Blocks.Add(paragraph);
    }

    private void AddList(ListBlock list, int depth)
    {
        var index = 1;
        foreach (var child in list)
        {
            if (child is not ListItemBlock item) continue;
            var prefix = $"{new string(' ', depth * 2)}{(list.IsOrdered ? $"{index++}. " : "- ")}";
            AddListItem(item, prefix, depth);
        }
    }

    private void AddListItem(ListItemBlock item, string prefix, int depth)
    {
        var first = true;
        foreach (var child in item)
        {
            if (first && child is ParagraphBlock paragraphBlock)
            {
                var paragraph = CreateParagraph(depth);
                paragraph.Inlines.Add(new Run { Text = prefix });
                AddInlines(paragraph.Inlines, paragraphBlock.Inline);
                Body.Blocks.Add(paragraph);
            }
            else
            {
                AddBlock(child, depth + 1);
            }
            first = false;
        }
    }

    private void AddQuote(QuoteBlock quote, int depth)
    {
        foreach (var child in quote)
        {
            if (child is ParagraphBlock paragraphBlock)
            {
                var paragraph = CreateParagraph(depth);
                paragraph.Inlines.Add(new Run { Text = "> " });
                AddInlines(paragraph.Inlines, paragraphBlock.Inline);
                Body.Blocks.Add(paragraph);
            }
            else
            {
                AddBlock(child, depth + 1);
            }
        }
    }

    private void AddCode(CodeBlock code, int depth)
    {
        var paragraph = CreateParagraph(depth);
        paragraph.FontFamily = new FontFamily("Cascadia Mono");
        paragraph.Inlines.Add(new Run { Text = code.Lines.ToString() });
        Body.Blocks.Add(paragraph);
    }

    private static Paragraph CreateParagraph(int depth = 0)
    {
        return new Paragraph();
    }

    private static void AddInlines(InlineCollection target, ContainerInline? source)
    {
        if (source is null) return;
        for (var child = source.FirstChild; child is not null; child = child.NextSibling)
            AddInline(target, child);
    }

    private static void AddInline(InlineCollection target, Markdig.Syntax.Inlines.Inline source)
    {
        switch (source)
        {
            case LiteralInline literal:
                target.Add(new Run { Text = literal.Content.ToString() });
                break;
            case LineBreakInline:
                target.Add(new LineBreak());
                break;
            case CodeInline code:
                target.Add(new Run { Text = code.Content, FontFamily = new FontFamily("Cascadia Mono") });
                break;
            case EmphasisInline emphasis:
                AddInlines(target, emphasis);
                break;
            case LinkInline link:
                AddInlines(target, link);
                break;
            case ContainerInline container:
                AddInlines(target, container);
                break;
        }
    }
}
