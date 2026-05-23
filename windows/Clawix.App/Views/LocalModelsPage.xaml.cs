using System.Collections.ObjectModel;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class LocalModelsPage : Page
{
    public ObservableCollection<LocalModelInfo> Models { get; } = new();

    public LocalModelsPage()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshModels();
    }

    private void Refresh_Click(object sender, RoutedEventArgs e)
    {
        RefreshModels();
    }

    private void OpenModelsFolder_Click(object sender, RoutedEventArgs e)
    {
        var directory = LocalModelInventory.DefaultModelsDirectory();
        Directory.CreateDirectory(directory);
        App.Services.Shell.Open(directory);
        RefreshModels();
    }

    private void RefreshModels()
    {
        var directory = LocalModelInventory.DefaultModelsDirectory();
        var models = LocalModelInventory.Snapshot(directory);
        Models.Clear();
        foreach (var model in models)
        {
            Models.Add(model);
        }

        var installed = models.Count(model => model.Installed);
        SummaryText.Text = $"{installed} of {models.Count} models installed";
    }
}
