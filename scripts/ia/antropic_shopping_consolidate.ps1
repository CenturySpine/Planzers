# ============================================================
# Test API IA - consolidation liste de courses
# Providers supportes : Anthropic, Google (Gemini)
# - Demande le modele (determine le provider)
# - Demande la cle API correspondante
# - Trace toutes les etapes
# - Affiche le resultat brut + extrait le tool_use
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# ETAPE 1 : Choix du modele (determine le provider)
# ============================================================
Write-Host "=== ETAPE 1/7 : Choix du modele ===" -ForegroundColor Cyan
Write-Host "Modeles disponibles :"
Write-Host "  1) claude-haiku-4-5-20251001  [Anthropic]"
Write-Host "  2) claude-sonnet-4-6           [Anthropic]"
Write-Host "  3) claude-opus-4-7             [Anthropic]"
Write-Host "  4) gemini-2.0-flash            [Google]"
Write-Host "  5) gemini-2.5-flash            [Google]"

$modelChoice = Read-Host "Choisis le modele (1-5) ou colle un ID custom (prefixe 'gemini-' => Google)"
switch ($modelChoice.Trim()) {
  "1" { $model = "claude-haiku-4-5-20251001"; $provider = "anthropic" }
  "2" { $model = "claude-sonnet-4-6";          $provider = "anthropic" }
  "3" { $model = "claude-opus-4-7";            $provider = "anthropic" }
  "4" { $model = "gemini-2.0-flash";           $provider = "gemini"    }
  "5" { $model = "gemini-2.5-flash";           $provider = "gemini"    }
  default {
    if ([string]::IsNullOrWhiteSpace($modelChoice)) { throw "Modele vide." }
    $model    = $modelChoice.Trim()
    $provider = if ($model.StartsWith("gemini")) { "gemini" } else { "anthropic" }
  }
}
Write-Host "Modele : $model  |  Provider : $provider"

# ============================================================
# ETAPE 2 : Saisie de la cle API (selon provider)
# ============================================================
Write-Host "`n=== ETAPE 2/7 : Saisie de la cle API ($provider) ===" -ForegroundColor Cyan
$keyLabel     = if ($provider -eq "anthropic") { "ANTHROPIC_API_KEY" } else { "GOOGLE_API_KEY" }
$secureApiKey = Read-Host "Colle la $keyLabel (saisie masquee)" -AsSecureString
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
try   { $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "Cle API vide." }

# ============================================================
# ETAPE 3 : Donnees d'entree (communes aux deux providers)
# ============================================================
Write-Host "`n=== ETAPE 3/7 : Construction des donnees d'entree ===" -ForegroundColor Cyan

$manualShoppingItems = @(
  @{ label = "Cafe moulu (grande boite 500g)";   quantityValue = 3;   quantityUnit = "unite" }
  @{ label = "Sucre blanc";                       quantityValue = 1;   quantityUnit = "kg"    }
  @{ label = "Farine";                            quantityValue = 1;   quantityUnit = "kg"    }
  @{ label = "Beurre doux (plaquette 250g)";      quantityValue = 2;   quantityUnit = "unite" }
  @{ label = "beurre demi sel (plaquette 250g)";  quantityValue = 2;   quantityUnit = "unite" }
  @{ label = "tomates";                           quantityValue = 1;   quantityUnit = "kg"    }
  @{ label = "biere 75cl";                        quantityValue = 10;  quantityUnit = "unite" }
  @{ label = "Oeufs peti dej et picnique";        quantityValue = 30;  quantityUnit = "unite" }
  @{ label = "carotte (apero)";                   quantityValue = 10;  quantityUnit = "unite" }
)

$recipeIngredients = @(
  @{ label = "Reblochon";                   quantityValue = 3;   quantityUnit = "unite" }
  @{ label = "Pomme de terre";              quantityValue = 3;   quantityUnit = "kg"    }
  @{ label = "oignons";                     quantityValue = 6;   quantityUnit = "unite" }
  @{ label = "Creme fraiche";               quantityValue = 1;   quantityUnit = "L"     }
  @{ label = "tranches de lard";            quantityValue = 10;  quantityUnit = "unite" }
  @{ label = "Salade";                      quantityValue = 5;   quantityUnit = "unite" }
  @{ label = "Lait";                        quantityValue = 250; quantityUnit = "ml"    }
  @{ label = "chocolat noir tablette 220g"; quantityValue = 5;   quantityUnit = "unite" }
  @{ label = "oeufs";                       quantityValue = 10;  quantityUnit = "unite" }
  @{ label = "Diots";                       quantityValue = 17;  quantityUnit = "unite" }
  @{ label = "Polenta";                     quantityValue = 3;   quantityUnit = "kg"    }
  @{ label = "salade";                      quantityValue = 5;   quantityUnit = "unite" }
)

Write-Host "manualShoppingItems: $($manualShoppingItems.Count) lignes"
Write-Host "recipeIngredients:   $($recipeIngredients.Count) lignes"

# ============================================================
# ETAPE 4 : Prompts et schema tool (communs aux deux providers)
# ============================================================
Write-Host "`n=== ETAPE 4/7 : Construction prompts et schema ===" -ForegroundColor Cyan

$systemPrompt = @"
Tu es un assistant specialise dans la consolidation de listes d ingredients culinaires.
Regles de fusion :
- Fusionner uniquement si le nom de base est identique ou quasi-identique.
- Ne pas fusionner des ingredients semantiquement differents.
- Convertir les unites compatibles avant addition (g/kg, ml/l).
- Si les unites sont incompatibles, garder des lignes separees.
- sourceType doit valoir manual, recipe, ou mixed selon l origine consolidee.
- Pour chaque ingredient consolide, assigne un categoryId parmi les identifiants fournis dans le prompt. Choisis la categorie la plus precise. Utilise 'divers' si aucune categorie ne convient.
"@

$categoriesLine = "animaux (Animaux), bebe (Bebe), boissons (Boissons), boucherie (Boucherie), boulangerie-viennoiserie (Boulangerie & Viennoiserie), conserves (Conserves), cremerie (Cremerie), divers (Divers), entretien (Entretien), epicerie-salee (Epicerie salee), epicerie-sucree (Epicerie sucree), fruits-et-legumes (Fruits et legumes), hygiene (Hygiene), maison (Maison), petit-dejeuner-et-gouter (Petit-dejeuner et gouter), poissonnerie (Poissonnerie), rayon-frais (Rayon frais), surgeles (Surgeles)"

$userPrompt = @"
Consolide les deux tableaux suivants.
summary.*OriginalLineCount doit correspondre au nombre de lignes d entree utilisees.
Pour chaque ligne consolidee, renseigne les compteurs manualOriginalLineCount et recipeOriginalLineCount utilises pour cette ligne.
Pour chaque ingredient consolide, assigne un categoryId parmi : $categoriesLine.

manualShoppingItems:
$($manualShoppingItems | ConvertTo-Json -Depth 10 -Compress)

recipeIngredients:
$($recipeIngredients | ConvertTo-Json -Depth 10 -Compress)
"@

# Schema JSON commun (JSON Schema standard, compatible Anthropic et Gemini)
$toolName        = "consolidate_shopping_list"
$toolDescription = "Retourne la liste de courses consolidee a partir des deux tableaux fournis."
$toolParameters  = @{
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
        required   = @("itemLabel", "quantityValue", "quantityUnit", "sourceType", "categoryId", "manualOriginalLineCount", "recipeOriginalLineCount")
        properties = @{
          itemLabel               = @{ type = "string";  description = "Nom consolide de l ingredient" }
          quantityValue           = @{ type = "number";  description = "Quantite totale consolidee" }
          quantityUnit            = @{ type = "string";  description = "Unite apres conversion eventuelle" }
          sourceType              = @{ type = "string";  enum = @("manual", "recipe", "mixed") }
          categoryId              = @{
            type        = "string"
            description = "Identifiant de la categorie de course. Utiliser 'divers' si aucune ne convient."
            enum        = @(
              "animaux", "bebe", "boissons", "boucherie", "boulangerie-viennoiserie",
              "conserves", "cremerie", "divers", "entretien", "epicerie-salee",
              "epicerie-sucree", "fruits-et-legumes", "hygiene", "maison",
              "petit-dejeuner-et-gouter", "poissonnerie", "rayon-frais", "surgeles"
            )
          }
          manualOriginalLineCount = @{ type = "integer"; description = "Nombre de lignes manual fusionnees dans cette entree" }
          recipeOriginalLineCount = @{ type = "integer"; description = "Nombre de lignes recipe fusionnees dans cette entree" }
          sourceItems             = @{
            type        = "array"
            description = "Lignes d entree ayant contribue a la consolidation. Renseigne uniquement si sourceType est mixed."
            items       = @{
              type       = "object"
              required   = @("source", "originalLabel", "originalQuantityValue", "originalQuantityUnit")
              properties = @{
                source                = @{ type = "string"; enum = @("manual", "recipe"); description = "Tableau d origine de la ligne" }
                originalLabel         = @{ type = "string"; description = "Label original de la ligne d entree" }
                originalQuantityValue = @{ type = "number"; description = "Quantite originale avant consolidation" }
                originalQuantityUnit  = @{ type = "string"; description = "Unite originale avant conversion" }
              }
            }
          }
        }
      }
    }
  }
}

Write-Host "Prompts et schema construits."

# ============================================================
# ETAPE 5 : Construction endpoint + headers + body (par provider)
# ============================================================
Write-Host "`n=== ETAPE 5/7 : Construction requete HTTP ($provider) ===" -ForegroundColor Cyan

if ($provider -eq "anthropic") {

  $endpoint = "https://api.anthropic.com/v1/messages"
  $headers  = @{
    "x-api-key"         = $apiKey
    "anthropic-version" = "2023-06-01"
  }
  $bodyObject = @{
    model       = $model
    max_tokens  = 5000
    temperature = 0.1
    system      = $systemPrompt
    tools       = @(@{
      name         = $toolName
      description  = $toolDescription
      input_schema = $toolParameters
    })
    tool_choice = @{ type = "tool"; name = $toolName }
    messages    = @(@{ role = "user"; content = $userPrompt })
  }

} else {

  # Gemini : la cle est dans l'URL, pas dans les headers
  $endpoint   = "https://generativelanguage.googleapis.com/v1beta/models/$($model):generateContent?key=$apiKey"
  $headers    = @{}
  $bodyObject = @{
    system_instruction = @{ parts = @(@{ text = $systemPrompt }) }
    contents           = @(@{ role = "user"; parts = @(@{ text = $userPrompt }) })
    tools              = @(@{
      function_declarations = @(@{
        name        = $toolName
        description = $toolDescription
        parameters  = $toolParameters
      })
    })
    tool_config       = @{ function_calling_config = @{ mode = "ANY" } }
    generation_config = @{ temperature = 0.1; maxOutputTokens = 5000; thinkingConfig = @{ thinkingBudget = 0 } }
  }

}

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObject | ConvertTo-Json -Depth 20))
Write-Host "Endpoint : $endpoint"
Write-Host "Body pret. Taille : $($bodyBytes.Length) octets"

# ============================================================
# ETAPE 6 : Appel API
# ============================================================
Write-Host "`n=== ETAPE 6/7 : Appel API ($provider) ===" -ForegroundColor Cyan

$response = Invoke-WebRequest `
  -Method Post `
  -Uri $endpoint `
  -Headers $headers `
  -ContentType "application/json; charset=utf-8" `
  -Body $bodyBytes `
  -TimeoutSec 120

Write-Host "HTTP Status: $($response.StatusCode)"

# Decode UTF-8 explicitement pour eviter les caracteres corrompus (PS 5.1)
$responseText = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())

# ============================================================
# ETAPE 7 : Affichage et extraction du resultat (par provider)
# ============================================================
Write-Host "`n=== ETAPE 7/7 : Affichage de la reponse ===" -ForegroundColor Cyan
Write-Host "--- Reponse brute ---"
Write-Output $responseText

Write-Host "`n--- Extraction resultat consolide ---" -ForegroundColor Green
$parsed = $responseText | ConvertFrom-Json

$aiResult = $null
if ($provider -eq "anthropic") {
  $toolBlock = $parsed.content | Where-Object { $_.type -eq "tool_use" } | Select-Object -First 1
  if ($toolBlock) {
    $toolBlock.input | ConvertTo-Json -Depth 10
    $aiResult = $toolBlock.input
  } else {
    Write-Warning "Aucun bloc tool_use trouve dans la reponse."
  }
} else {
  $funcBlock = $parsed.candidates[0].content.parts | Where-Object { $_.functionCall } | Select-Object -First 1
  if ($funcBlock) {
    $funcBlock.functionCall.args | ConvertTo-Json -Depth 10
    $aiResult = $funcBlock.functionCall.args
  } else {
    Write-Warning "Aucun bloc functionCall trouve dans la reponse."
  }
}

# ============================================================
# Affichage groupe par categorie
# ============================================================
if ($aiResult -and $aiResult.consolidatedItems) {
  $categoryLabels = @{
    "animaux"                  = "Animaux"
    "bebe"                     = "Bebe"
    "boissons"                 = "Boissons"
    "boucherie"                = "Boucherie"
    "boulangerie-viennoiserie" = "Boulangerie & Viennoiserie"
    "conserves"                = "Conserves"
    "cremerie"                 = "Cremerie"
    "divers"                   = "Divers"
    "entretien"                = "Entretien"
    "epicerie-salee"           = "Epicerie salee"
    "epicerie-sucree"          = "Epicerie sucree"
    "fruits-et-legumes"        = "Fruits et legumes"
    "hygiene"                  = "Hygiene"
    "maison"                   = "Maison"
    "petit-dejeuner-et-gouter" = "Petit-dejeuner et gouter"
    "poissonnerie"             = "Poissonnerie"
    "rayon-frais"              = "Rayon frais"
    "surgeles"                 = "Surgeles"
  }

  $grouped = $aiResult.consolidatedItems | Group-Object -Property categoryId

  Write-Host "`n=== LISTE DE COURSES PAR CATEGORIE ===" -ForegroundColor Yellow

  $summary = $aiResult.summary
  if ($summary) {
    Write-Host ("  Lignes manuel en entree  : {0}" -f $summary.manualOriginalLineCount)
    Write-Host ("  Lignes recette en entree : {0}" -f $summary.recipeOriginalLineCount)
    Write-Host ("  Items consolides         : {0}" -f @($aiResult.consolidatedItems).Count)
  }

  foreach ($group in ($grouped | Sort-Object Name)) {
    $catId    = $group.Name
    $catLabel = if ($categoryLabels.ContainsKey($catId)) { $categoryLabels[$catId] } else { $catId }
    Write-Host ("`n  [{0}]" -f $catLabel.ToUpper()) -ForegroundColor Cyan

    foreach ($item in $group.Group) {
      $qty      = $item.quantityValue
      $unit     = $item.quantityUnit
      $label    = $item.itemLabel
      $srcBadge = switch ($item.sourceType) {
        "manual" { "[M]"   }
        "recipe" { "[R]"   }
        default  { "[M+R]" }
      }
      Write-Host ("    {0}  {1} {2} {3}" -f $srcBadge, $qty, $unit, $label)
    }
  }

  Write-Host ""
}
