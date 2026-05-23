using System.Collections.ObjectModel;
using Clawix.Core;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Clawix.App.Views;

public sealed partial class ChatView : UserControl
{
    public ObservableCollection<WireMessage> Messages { get; } = new();
    public string Title { get; private set; } = "Welcome to Clawix";
    private IReadOnlyList<MessageFindMatch> _findMatches = [];
    private int _currentFindIndex;

    public ChatView()
    {
        InitializeComponent();
        FindBar.QueryChanged += (_, query) => UpdateFindMatches(query);
        FindBar.PreviousRequested += (_, _) => MoveFind(previous: true);
        FindBar.NextRequested += (_, _) => MoveFind(previous: false);
        FindBar.CloseRequested += (_, _) => CloseFindBar();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var state = App.Services.State;
        state.ComposerFocusRequested += () => DispatcherQueue.TryEnqueue(Composer.FocusInput);
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.CurrentMessages))
                DispatcherQueue.TryEnqueue(() =>
                {
                    Messages.Clear();
                    foreach (var m in state.CurrentMessages) Messages.Add(m);
                    UpdateFindMatches();
                });
            if (args.PropertyName == nameof(state.CurrentChat))
                DispatcherQueue.TryEnqueue(() =>
                {
                    Title = state.CurrentChat?.Title ?? "Welcome to Clawix";
                    TitleText.Text = Title;
                    CloseFindBar();
                });
        };
    }

    private void OpenFind_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        OpenFindBar();
        args.Handled = true;
    }

    private void OpenFindBar()
    {
        FindBar.Visibility = Visibility.Visible;
        FindBar.FocusQuery();
        UpdateFindMatches();
    }

    private void CloseFindBar()
    {
        FindBar.Visibility = Visibility.Collapsed;
        FindBar.Reset();
        _findMatches = [];
        _currentFindIndex = 0;
        Composer.FocusInput();
    }

    private void UpdateFindMatches(string? query = null)
    {
        query ??= FindBar.Query;
        _findMatches = MessageFindIndex.Find(Messages, query);
        _currentFindIndex = _findMatches.Count == 0 ? 0 : Math.Min(_currentFindIndex, _findMatches.Count - 1);
        SyncFindStatus();
        ScrollToCurrentMatch();
    }

    private void MoveFind(bool previous)
    {
        if (_findMatches.Count == 0) return;

        _currentFindIndex = previous
            ? MessageFindIndex.PreviousIndex(_currentFindIndex, _findMatches.Count)
            : MessageFindIndex.NextIndex(_currentFindIndex, _findMatches.Count);
        SyncFindStatus();
        ScrollToCurrentMatch();
    }

    private void SyncFindStatus()
    {
        FindBar.SetMatchStatus(
            MessageFindIndex.CounterText(_currentFindIndex, _findMatches.Count),
            _findMatches.Count > 0);
    }

    private void ScrollToCurrentMatch()
    {
        if (_findMatches.Count == 0) return;

        var match = _findMatches[_currentFindIndex];
        var message = Messages.FirstOrDefault(candidate => candidate.Id == match.MessageId);
        if (message is not null)
            MessageList.ScrollIntoView(message);
    }
}
