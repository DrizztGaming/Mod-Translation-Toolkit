using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using Forms = System.Windows.Forms;
using ModTranslationToolkit.Models;
using ModTranslationToolkit.Services;
using ModTranslationToolkit.ViewModels;

namespace ModTranslationToolkit;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm = new();
    private string _currentPath = "";

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _vm;
        Tag = "";
    }

    private void ChooseFolder_Click(object sender, RoutedEventArgs e)
    {
        using var dlg = new Forms.FolderBrowserDialog { UseDescriptionForTitle = true, Description = "Choose game or mod folder" };
        if (dlg.ShowDialog() != Forms.DialogResult.OK) return;
        _currentPath = dlg.SelectedPath;
        Tag = _currentPath;
        _vm.Status = _currentPath;
    }

    private async void Scan_Click(object sender, RoutedEventArgs e)
    {
        if (!Directory.Exists(_currentPath))
        {
            System.Windows.MessageBox.Show("Choose a valid folder first.");
            return;
        }

        try
        {
            _vm.Status = "Scanning...";
            await Task.Yield();

            var tab = FindAncestor<TabItem>((DependencyObject)sender);
            var header = tab?.Header?.ToString() ?? "";

            List<TranslationEntry> entries;
            if (header.Contains("Project Zomboid", StringComparison.OrdinalIgnoreCase))
            {
                entries = ProjectZomboidScanner.Scan(_currentPath, "EN", "PL");
            }
            else if (header.Contains("RimWorld", StringComparison.OrdinalIgnoreCase))
            {
                entries = RimWorldScanner.ScanLanguageFolders(_currentPath, "English", "Polish");
                if (entries.Count == 0)
                    entries = RimWorldScanner.ScanEnglishDefs(_currentPath);
            }
            else
            {
                entries = [];
            }

            _vm.ReplaceEntries(entries);
            _vm.Status = $"Scan finished: {entries.Count} entries.";
        }
        catch (Exception ex)
        {
            _vm.Status = ex.Message;
            System.Windows.MessageBox.Show(ex.ToString(), "Scan error");
        }
    }

    private void Filter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is not System.Windows.Controls.ComboBox cb ||
            cb.SelectedItem is not ComboBoxItem item) return;
        if (Enum.TryParse<EntryFilter>(item.Tag?.ToString(), out var f))
            _vm.Filter = f;
    }

    private void ExportCsv_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog { Filter = "CSV (*.csv)|*.csv", FileName = "translation.csv" };
        if (dlg.ShowDialog() != true) return;
        CsvService.Export(dlg.FileName, _vm.Entries, "en", "pl");
        _vm.Status = $"CSV exported: {dlg.FileName}";
    }

    private void ImportCsv_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Filter = "CSV (*.csv)|*.csv" };
        if (dlg.ShowDialog() != true) return;
        var map = CsvService.Import(dlg.FileName);
        int count = 0;
        foreach (var entry in _vm.Entries)
            if (map.TryGetValue(entry.Identity, out var value))
            { entry.Translation = value; count++; }
        _vm.EntriesView.Refresh();
        _vm.Status = $"Imported: {count} entries.";
    }

    private void Api_Click(object sender, RoutedEventArgs e) =>
        System.Windows.MessageBox.Show(
            "Native .NET API provider migration is the next v1 step.\nLibreTranslate service is already present in the codebase.",
            "API / Translation");

    private static T? FindAncestor<T>(DependencyObject? current) where T : DependencyObject
    {
        while (current is not null)
        {
            if (current is T value) return value;
            current = System.Windows.Media.VisualTreeHelper.GetParent(current);
        }
        return null;
    }
}
