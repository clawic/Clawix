using System.Collections.ObjectModel;
using Clawix.Core;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class SidebarView : UserControl
{
    public ObservableCollection<WireSession> Sessions { get; } = new();
    public ObservableCollection<WireSession> PinnedSessions { get; } = new();
    public ObservableCollection<WireProject> Projects { get; } = new();
    private IReadOnlyList<WireSession> _allSessions = [];
    private WireProject? _selectedProject;

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
                    RefreshPinnedSessions();
                    RefreshSessions();
                });
            if (args.PropertyName == nameof(state.Projects))
                DispatcherQueue.TryEnqueue(() =>
                {
                    RefreshProjects(state.Projects);
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
        RefreshPinnedSessions();
        RefreshProjects(state.Projects);
        RefreshSessions();
        BridgeStatusText.Text = state.BridgeStateLabel;
        RateLimits.Render(state.RateLimits?.Primary, state.RateLimits?.Secondary);
        RateLimits.RenderCredits(state.RateLimits?.Credits);
    }

    private async void ChatList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ChatList.SelectedItem is WireSession chat)
        {
            PinnedList.SelectedItem = null;
            await App.Services.State.SelectChatAsync(chat);
        }
    }

    private async void PinnedList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (PinnedList.SelectedItem is WireSession chat)
        {
            ChatList.SelectedItem = null;
            await App.Services.State.SelectChatAsync(chat);
        }
    }

    private void NewChat_Click(object sender, RoutedEventArgs e)
    {
        ChatList.SelectedItem = null;
        PinnedList.SelectedItem = null;
        App.Services.State.StartNewChat();
    }

    private async void TogglePin_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is WireSession chat)
            await App.Services.State.SetPinnedAsync(chat, !chat.IsPinned);
    }

    private void ProjectList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _selectedProject = ProjectList.SelectedItem as WireProject;
        ChatList.SelectedItem = null;
        UpdateProjectChromeVisibility();
        RefreshSessions();
    }

    private void AllChats_Click(object sender, RoutedEventArgs e)
    {
        ProjectList.SelectedItem = null;
        _selectedProject = null;
        UpdateProjectChromeVisibility();
        RefreshSessions();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshPinnedSessions();
        RefreshSessions();
    }

    private void RefreshPinnedSessions()
    {
        var selectedId = (PinnedList.SelectedItem as WireSession)?.Id;
        var filtered = SessionSearch.FilterPinned(_allSessions, SearchBox.Text);
        PinnedSessions.Clear();
        WireSession? selected = null;
        foreach (var chat in filtered)
        {
            PinnedSessions.Add(chat);
            if (chat.Id == selectedId) selected = chat;
        }

        PinnedList.SelectedItem = selected;
        var hasPinned = PinnedSessions.Count > 0;
        PinnedHeader.Visibility = hasPinned ? Visibility.Visible : Visibility.Collapsed;
        PinnedList.Visibility = hasPinned ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshSessions()
    {
        var selectedId = (ChatList.SelectedItem as WireSession)?.Id;
        var filtered = SessionSearch.FilterByProject(_allSessions, _selectedProject, SearchBox.Text);
        Sessions.Clear();
        WireSession? selected = null;
        foreach (var chat in filtered)
        {
            Sessions.Add(chat);
            if (chat.Id == selectedId) selected = chat;
        }
        ChatList.SelectedItem = selected;
    }

    private void RefreshProjects(IReadOnlyList<WireProject> projects)
    {
        var selectedId = _selectedProject?.Id;
        Projects.Clear();
        WireProject? selected = null;
        foreach (var project in projects)
        {
            Projects.Add(project);
            if (project.Id == selectedId) selected = project;
        }

        _selectedProject = selected;
        ProjectList.SelectedItem = selected;
        UpdateProjectChromeVisibility();
    }

    private void UpdateProjectChromeVisibility()
    {
        var hasProjects = Projects.Count > 0;
        ProjectsHeader.Visibility = hasProjects ? Visibility.Visible : Visibility.Collapsed;
        ProjectList.Visibility = hasProjects ? Visibility.Visible : Visibility.Collapsed;
        AllChatsButton.Visibility = _selectedProject is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        // Open Settings as a separate window so chat stays visible.
        var win = new SettingsWindow();
        win.Activate();
    }
}
