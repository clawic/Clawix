using System.Collections.ObjectModel;
using Clawix.Core;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class SidebarView : UserControl
{
    public ObservableCollection<WireSession> Sessions { get; } = new();
    private IReadOnlyList<WireSession> _allSessions = [];

    public SidebarView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var state = App.Services.State;
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.Sessions))
                DispatcherQueue.TryEnqueue(() =>
                {
                    _allSessions = state.Sessions;
                    RefreshSessions();
                });
            if (args.PropertyName == nameof(state.BridgeStateLabel))
                DispatcherQueue.TryEnqueue(() => BridgeStatusText.Text = state.BridgeStateLabel);
            if (args.PropertyName == nameof(state.RateLimits))
                DispatcherQueue.TryEnqueue(() =>
                {
                    RateLimits.Render(state.RateLimits?.Primary, state.RateLimits?.Secondary);
                    RateLimits.RenderCredits(state.RateLimits?.Credits);
                });
        };
        _allSessions = state.Sessions;
        RefreshSessions();
        BridgeStatusText.Text = state.BridgeStateLabel;
        RateLimits.Render(state.RateLimits?.Primary, state.RateLimits?.Secondary);
        RateLimits.RenderCredits(state.RateLimits?.Credits);
    }

    private async void ChatList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ChatList.SelectedItem is WireSession chat)
            await App.Services.State.SelectChatAsync(chat);
    }

    private void NewChat_Click(object sender, RoutedEventArgs e)
    {
        ChatList.SelectedItem = null;
        App.Services.State.StartNewChat();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshSessions();
    }

    private void RefreshSessions()
    {
        var selectedId = (ChatList.SelectedItem as WireSession)?.Id;
        var filtered = SessionSearch.Filter(_allSessions, SearchBox.Text);
        Sessions.Clear();
        WireSession? selected = null;
        foreach (var chat in filtered)
        {
            Sessions.Add(chat);
            if (chat.Id == selectedId) selected = chat;
        }
        ChatList.SelectedItem = selected;
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        // Open Settings as a separate window so chat stays visible.
        var win = new SettingsWindow();
        win.Activate();
    }
}
