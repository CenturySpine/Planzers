# Storage CORS configuration

This folder contains versioned CORS policies for Firebase Storage buckets.

## Files

- `preview.cors.json`: permissive CORS policy for preview/dev bucket.
- `prod.cors.json`: strict CORS policy for production bucket.

## Apply the policies

From the repository root:

```powershell
gsutil cors set infra/storage-cors/preview.cors.json gs://planerz-preview.firebasestorage.app
gsutil cors set infra/storage-cors/prod.cors.json gs://planerz.firebasestorage.app
```

## Verify the active policies

```powershell
gsutil cors get gs://planerz-preview.firebasestorage.app
gsutil cors get gs://planerz.firebasestorage.app
```

## Notes

- CORS propagation can take a few minutes.
- Keep this folder in git so infrastructure config stays reproducible.
