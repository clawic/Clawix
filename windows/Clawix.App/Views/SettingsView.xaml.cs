using System.Linq;
using Clawix.App.Views.Settings;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;

namespace Clawix.App.Views;

public sealed partial class SettingsView : UserControl
{
    private readonly NavigationView _nav;

    public SettingsView()
    {
        InitializeComponent();
        _nav = (NavigationView)Content;
        _nav.SelectionChanged += Nav_SelectionChanged;
        NavigateTo("general");
    }

    public void NavigateTo(string tag)
    {
        foreach (var item in _nav.MenuItems.OfType<NavigationViewItem>())
        {
            if ((item.Tag as string) != tag) continue;
            _nav.SelectedItem = item;
            NavigateTag(tag);
            return;
        }

        NavigateTag("general");
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag) return;
        NavigateTag(tag);
    }

    private void NavigateTag(string tag)
    {
        Type page = tag switch
        {
            "general"     => typeof(GeneralPage),
            "account"     => typeof(AccountPage),
            "models"      => typeof(ModelsPage),
            "localModels" => typeof(LocalModelsPage),
            "dictation"   => typeof(DictationSettingsPage),
            "quickAsk"    => typeof(QuickAskSettingsPage),
            "secrets"     => typeof(SecretsPage),
            "mcp"         => typeof(MCPPage),
            "database"    => typeof(DatabasePage),
            "updates"     => typeof(UpdatesPage),
            "pairing"     => typeof(PairingPage),
            "privacy"     => typeof(PrivacyPage),
            "about"       => typeof(AboutPage),
            _             => typeof(GeneralPage),
        };
        ContentFrame.Navigate(page, null, new EntranceNavigationTransitionInfo());
    }
}
