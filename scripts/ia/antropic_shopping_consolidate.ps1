# ============================================================
# Test manuel Anthropic API - Saisie clé + choix modèle à chaque exécution
# - Demande la clé API à chaque lancement
# - Demande le modèle à utiliser
# - Trace toutes les étapes
# - N'effectue AUCUN traitement de la réponse
# - Affiche uniquement le résultat brut de l'API
# ============================================================

$ErrorActionPreference = "Stop"

Write-Host "=== ETAPE 1/8 : Saisie de la cle API Anthropic ===" -ForegroundColor Cyan

$secureApiKey = Read-Host "Colle la cle ANTHROPIC_API_KEY (saisie masquee)" -AsSecureString
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
try {
  $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}
finally {
  [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw "Cle API vide."
}

Write-Host "`n=== ETAPE 2/8 : Choix du modele Anthropic ===" -ForegroundColor Cyan
Write-Host "Modeles disponibles :"
Write-Host "  1) claude-haiku-4-5-20251001"
Write-Host "  2) claude-sonnet-4-6"
Write-Host "  3) claude-opus-4-6"

$modelChoice = Read-Host "Choisis le modele (1, 2, 3) ou colle un ID custom"
switch ($modelChoice.Trim()) {
  "1" { $model = "claude-haiku-4-5-20251001" }
  "2" { $model = "claude-sonnet-4-6" }
  "3" { $model = "claude-opus-4-7" }
  default {
    if ([string]::IsNullOrWhiteSpace($modelChoice)) {
      throw "Modele vide."
    }
    $model = $modelChoice.Trim()
  }
}

$endpoint = "https://api.anthropic.com/v1/messages"

Write-Host "Endpoint: $endpoint"
Write-Host "Model: $model"

Write-Host "`n=== ETAPE 3/8 : Construction des donnees d'entree ===" -ForegroundColor Cyan

# Tableau 1 = liste de courses manuelle
$manualShoppingItems = @(
  @{ label = "Cafe moulu (grande boite 500g)";   quantityValue = 3;  quantityUnit = "unite" }
  @{ label = "Sucre blanc";                      quantityValue = 1;  quantityUnit = "kg" }
  @{ label = "Farine";                           quantityValue = 1;  quantityUnit = "kg" }
  @{ label = "Beurre doux (plaquette 250g)";     quantityValue = 2;  quantityUnit = "unite" }
  @{ label = "beurre demi sel (plaquette 250g)"; quantityValue = 2;  quantityUnit = "unite" }
  @{ label = "tomates";                          quantityValue = 1;  quantityUnit = "kg" }
  @{ label = "biere 75cl";                       quantityValue = 10; quantityUnit = "unite" }
  @{ label = "Oeufs peti dej et picnique";       quantityValue = 30; quantityUnit = "unite" }
  @{ label = "carottes (battonets, apero)";      quantityValue = 1; quantityUnit = "kg" }
  @{ label = "lait sans lactose";                quantityValue = 2;  quantityUnit = "L" }
)

# Tableau 2 = ingredients recettes
$recipeIngredients = @(
  @{ label = "Reblochon";                   quantityValue = 3;  quantityUnit = "unite" }
  @{ label = "Pomme de terre";              quantityValue = 3;  quantityUnit = "kg" }
  @{ label = "oignons";                     quantityValue = 6;  quantityUnit = "unite" }
  @{ label = "Creme fraiche";               quantityValue = 1;  quantityUnit = "L" }
  @{ label = "tranches de lard";            quantityValue = 10; quantityUnit = "unite" }

  @{ label = "Salades";                     quantityValue = 5;  quantityUnit = "unite" }

  @{ label = "Lait demi ecrémé";            quantityValue = 250; quantityUnit = "ml" }
  @{ label = "chocolat noir tablette 220g"; quantityValue = 5;  quantityUnit = "unite" }
  @{ label = "oeufs";                       quantityValue = 10; quantityUnit = "unite" }
  @{ label = "sucre";                       quantityValue = 250; quantityUnit = "g" }

  @{ label = "Diots";                       quantityValue = 17; quantityUnit = "unite" }
  @{ label = "Polenta";                     quantityValue = 3;  quantityUnit = "kg" }
  @{ label = "salade";                      quantityValue = 5;  quantityUnit = "unite" }
  @{ label = "carottes (rapées, entrée)";    quantityValue = 1;  quantityUnit = "kg" }
)

Write-Host "manualShoppingItems: $($manualShoppingItems.Count) lignes"
Write-Host "recipeIngredients:   $($recipeIngredients.Count) lignes"

Write-Host "`n=== ETAPE 4/8 : Construction prompts ===" -ForegroundColor Cyan

$systemPrompt = @"
Tu es un assistant specialise dans la consolidation de listes d ingredients culinaires.
Regles de fusion :
- Fusionner uniquement si le nom de base est identique ou quasi-identique.
- Ne pas fusionner des ingredients semantiquement differents.
- Convertir les unites compatibles avant addition (g/kg, ml/l).
- Si les unites sont incompatibles, garder des lignes separees.
- sourceType doit valoir manual, recipe, ou mixed selon l origine consolidee.
"@

$userPrompt = @"
Consolide les deux tableaux suivants.
summary.*OriginalLineCount doit correspondre au nombre de lignes d entree utilisees.
Pour chaque ligne consolidee, renseigne les compteurs manualOriginalLineCount et recipeOriginalLineCount utilises pour cette ligne.

manualShoppingItems:
$($manualShoppingItems | ConvertTo-Json -Depth 10 -Compress)

recipeIngredients:
$($recipeIngredients | ConvertTo-Json -Depth 10 -Compress)
"@

Write-Host "Prompts construits."

Write-Host "`n=== ETAPE 5/8 : Construction body HTTP ===" -ForegroundColor Cyan

$toolSchema = @{
  name        = "consolidate_shopping_list"
  description = "Retourne la liste de courses consolidee a partir des deux tableaux fournis."
  input_schema = @{
    type       = "object"
    required   = @("summary", "consolidatedItems")
    properties = @{
      summary = @{
        type       = "object"
        required   = @("manualOriginalLineCount", "recipeOriginalLineCount")
        properties = @{
          manualOriginalLineCount = @{ type = "integer"; description = "Nombre total de lignes en entree dans manualShoppingItems" }
          recipeOriginalLineCount = @{ type = "integer"; description = "Nombre total de lignes en entree dans recipeIngredients" }
        }
      }
      consolidatedItems = @{
        type  = "array"
        items = @{
          type       = "object"
          required   = @("itemLabel", "quantityValue", "quantityUnit", "sourceType", "manualOriginalLineCount", "recipeOriginalLineCount")
          properties = @{
            itemLabel               = @{ type = "string";  description = "Nom consolide de l ingredient" }
            quantityValue           = @{ type = "number";  description = "Quantite totale consolidee" }
            quantityUnit            = @{ type = "string";  description = "Unite apres conversion eventuelle" }
            sourceType              = @{ type = "string";  enum = @("manual", "recipe", "mixed") }
            manualOriginalLineCount = @{ type = "integer"; description = "Nombre de lignes manual fusionnees dans cette entree" }
            recipeOriginalLineCount = @{ type = "integer"; description = "Nombre de lignes recipe fusionnees dans cette entree" }
          }
        }
      }
    }
  }
}

$bodyObject = @{
  model       = $model
  max_tokens  = 5000
  system      = $systemPrompt
  tools       = @($toolSchema)
  tool_choice = @{ type = "tool"; name = "consolidate_shopping_list" }
  messages    = @(
    @{
      role    = "user"
      content = $userPrompt
    }
  )
  temperature = 0.1
}

$bodyJson = $bodyObject | ConvertTo-Json -Depth 20
Write-Host "Body JSON pret. Taille: $($bodyJson.Length) caracteres"

Write-Host "`n=== ETAPE 6/8 : Construction headers ===" -ForegroundColor Cyan

$headers = @{
  "x-api-key"         = $apiKey
  "anthropic-version" = "2023-06-01"
}

Write-Host "Headers prets."

Write-Host "`n=== ETAPE 7/8 : Appel API Anthropic ===" -ForegroundColor Cyan

$response = Invoke-WebRequest `
  -Method Post `
  -Uri $endpoint `
  -Headers $headers `
  -ContentType "application/json" `
  -Body $bodyJson `
  -TimeoutSec 120

Write-Host "HTTP Status: $($response.StatusCode)"

# Decode UTF-8 explicitement pour eviter les caracteres corrompus
$responseText = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())

Write-Host "`n=== ETAPE 8/8 : Affichage de la reponse API ===" -ForegroundColor Cyan
Write-Host "--- Reponse brute ---"
Write-Output $responseText

Write-Host "`n--- Extraction tool_use.input (resultat consolide) ---" -ForegroundColor Green
$parsed     = $responseText | ConvertFrom-Json
$toolResult = $parsed.content | Where-Object { $_.type -eq "tool_use" } | Select-Object -First 1
if ($toolResult) {
  $toolResult.input | ConvertTo-Json -Depth 10
} else {
  Write-Warning "Aucun bloc tool_use trouve dans la reponse."
}