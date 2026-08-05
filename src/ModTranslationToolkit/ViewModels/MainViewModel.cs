using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows.Data;
using ModTranslationToolkit.Models;

namespace ModTranslationToolkit.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    public ObservableCollection<TranslationEntry> Entries { get; } = [];
    public ICollectionView EntriesView { get; }

    private EntryFilter _filter;
    public EntryFilter Filter
    {
        get => _filter;
        set { _filter = value; OnPropertyChanged(); EntriesView.Refresh(); OnPropertyChanged(nameof(CountText)); }
    }

    private string _status = "Ready.";
    public string Status { get => _status; set { _status=value; OnPropertyChanged(); } }

    public string CountText => $"Entries: {EntriesView.Cast<object>().Count()} / {Entries.Count}";

    public MainViewModel()
    {
        EntriesView = CollectionViewSource.GetDefaultView(Entries);
        EntriesView.Filter = obj => obj is TranslationEntry e && Filter switch {
            EntryFilter.Missing => e.Missing,
            EntryFilter.Translated => e.Translated,
            EntryFilter.Identical => e.Identical,
            EntryFilter.Suspicious => e.Suspicious,
            _ => true
        };
    }

    public void ReplaceEntries(IEnumerable<TranslationEntry> entries)
    {
        Entries.Clear();
        foreach (var e in entries) Entries.Add(e);
        EntriesView.Refresh();
        OnPropertyChanged(nameof(CountText));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? n=null) =>
        PropertyChanged?.Invoke(this,new PropertyChangedEventArgs(n));
}
