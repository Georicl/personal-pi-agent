# Library routing

Use the smallest library set that expresses the requested figure clearly.

| Need | Preferred library | Official documentation |
|---|---|---|
| Base static plotting, axes, layout, PDF/PNG output | Matplotlib | https://matplotlib.org/stable/ |
| Statistical distributions and tidy-data plotting | Seaborn | https://seaborn.pydata.org/ |
| Data loading, reshaping and aggregation | pandas | https://pandas.pydata.org/docs/ |
| Numerical arrays and transformations | NumPy | https://numpy.org/doc/stable/ |
| Scientific calculations | SciPy | https://docs.scipy.org/doc/scipy/ |
| Grammar-of-graphics syntax | Plotnine | https://plotnine.org/ |
| Raster inspection and TIFF writing | Pillow | https://pillow.readthedocs.io/en/stable/ |
| Scientific TIFF metadata | tifffile | https://github.com/cgohlke/tifffile |
| Image measurements | scikit-image | https://scikit-image.org/docs/stable/ |
| Explicitly confirmed statistical models | Statsmodels | https://www.statsmodels.org/stable/ |
| Explicitly confirmed survival analysis | Lifelines | https://lifelines.readthedocs.io/ |
| Graph/network layouts | NetworkX | https://networkx.org/documentation/stable/ |

For CSV, TSV, JSON, Parquet, Feather, pickle, and Excel derivatives, prefer the shared load_table function. Supported Excel families include XLS, XLSX, XLSM, XLSB, and ODS when the corresponding engine can read the file.

Only load pandas pickle files from a source the user trusts, because Python pickle is executable serialization. NumPy files are loaded with `allow_pickle=False`.

Do not introduce AnnData or Scanpy in the first version of this workflow.

Use scientific_figure_library_docs for current API details. The tool restricts network lookup to the official documentation origins listed above.
